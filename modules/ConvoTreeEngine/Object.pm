package ConvoTreeEngine::Object;

use strict;
use warnings;

use ConvoTreeEngine::Mysql;

sub _prep_args {
	my $self = shift;

	return {} unless @_;

	return $_[0] if (ref($_[0]) || '') eq 'HASH';

	ConvoTreeEngine::Exception::Internal->throw(
		error => "odd number of parameters cannot be cast as hash",
	) if @_ % 2;

	for (my $i = 0; $i < @_; $i += 2) {
		ConvoTreeEngine::Exception::Internal->throw(
			error => "has keys must be defined",
		) unless defined $_[$i];
	}

	return {@_};
}

sub _prep_args_multi {
	my $self  = shift;
	my $count = shift;

	return {} unless @_;

	my @response;
	while (@_ && (ref($_[0]) || '') eq 'HASH') {
		push @response, shift;
	}

	if (@_) {
		push @response, $self->_prep_args(@_);
	}

	while (@response < $count) {
		push @response, {};
	}

	return @response;
}

sub _parse_query_attrs {
	my $self  = shift;
	my $attrs = shift;

	my @string;
	my @bits;

	if (defined $attrs->{group_by}) {
		$attrs->{group_by} = [$attrs->{group_by}] unless ref($attrs->{group_by} || '') eq 'ARRAY';
		my $string = 'GROUP BY ' . join(',', ('?') x @{$attrs->{group_by}});
		push @string, $string;
		push @bits,  @{$attrs->{group_by}};
		delete $attrs->{group_by};
		if (defined $attrs->{having}) {
			push @string, 'HAVING ' . delete $attrs->{having};
		}
	}
	else {
		delete $attrs->{having};
	}

	if (defined $attrs->{order_by}) {
		$attrs->{order_by} = [$attrs->{order_by}] unless ref($attrs->{order_by} || '') eq 'ARRAY';
		my $string = 'ORDER BY ' . join(',', ('?') x @{$attrs->{order_by}});
		push @string, $string;
		push @bits,  @{$attrs->{order_by}};
		delete $attrs->{order_by};
	}
	if (defined $attrs->{limit}) {
		push @string, 'LIMIT ?';
		push @bits, delete $attrs->{limit};
	}
	if (defined $attrs->{offset}) {
		push @string, 'OFFSET ?';
		push @bits, delete $attrs->{offset};
	}

	return join(' ', @string), \@bits;
}

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my ($attrString, $bits) = $invocant->_parse_query_attrs($attrs);

	my $whereString;
	my @whereString;
	my @input;
	if ($args->{WHERE}) {
		$whereString = $args->{WHERE};
	}
	else {
		foreach my $field (keys $args) {
			my $ref = ref($args->{$field}) || '';
			if ($ref eq 'ARRAY') {
				my $string = "$field IN (";
				my $hasUndef = 0;
				my @args;
				foreach my $value (@{$args->{$field}}) {
					if (defined $value) {
						$string .= '?, ';
						push @args, $value;
					}
					else {
						$hasUndef = 1;
					}
				}
				$string = substr($string, 0, -2) . ')';

				if ($hasUndef) {
					$string = "($field IS NULL OR $string)";
				}

				push @whereString, $string;
				push @input, @{$args->{$field}};
			}
			elsif ($ref eq 'HASH' && scalar(keys %{$args->{$field}}) == 1) {
				my ($key) = keys %{$args->{$field}};
				my $value = $args->{$field}{$key};
				if (!defined $value) {
					$key = 'IS' if $key eq '=';
					$key = 'IS NOT' if $key eq '!=';
					push @whereString, "$field $key NULL";
				}
				else {
					push @whereString, "$field $key ?";
					push @input, $value;
				}
			}
			else {
				if (defined $args->{$field}) {
					push @whereString, "$field = ?";
					push @input, $args->{$field};
				}
				else {
					push @whereString, "$field IS NULL";
				}
			}
		}
	}

	$whereString ||= join ' AND ', @whereString;
	$whereString = "WHERE $whereString" if $whereString;
	push @input, @$bits;
	my $table = $invocant->_table;
	my $fields = $invocant->_fields;
	my $query = qq/
		SELECT $fields FROM $table
		$whereString
		$attrString
	/;
	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

sub find {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);
	my @result = $invocant->search($args, $attrs);

	if (@result > 1) {
		ConvoTreeEngine::Exception::DuplicateRecord->throw(
			args => $args,
		);
	}

	return $result[0];
}

sub findOrDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	return $result if $result;
	ConvoTreeEngine::Exception::RecordNotFound->throw(
		args => $args,
	);
}

sub findAndDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	ConvoTreeEngine::Exception::DuplicateRecord->throw(
		args => $args,
	) if $result;

	return;
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my @ro = $self->_read_only_fields;
	foreach my $field (@ro) {
		if (exists $args->{$field}) {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$field' field cannot be updated on the 'Element' object",
				args  => $args,
			) if (defined $args->{$field} xor defined $self->$field()) || (defined $args->{$field} && $args->{$field} ne $self->$field());
		}
	}

	my @sets;
	my @bits;
	foreach my $arg (keys %$args) {
		push @sets, "$arg = ?";
		push @bits, $args->{$arg};
	}
	my $sets = join ', ', @sets;
	push @bits, $self->id;

	my $table = $self->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/UPDATE $table SET $sets WHERE id = ?;/,
		\@bits,
	);

	return $self->refresh;
}

sub delete {
	my $self = shift;

	my $table = $self->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/DELETE FROM $table WHERE id = ?;/,
		[$self->id],
	);

	return;
}

sub refresh {
	my $self = shift;
	my $found = $self->find({id => $self->id});
	%$self = %$found;

	return $self;
}

sub all {
	my $invocant = shift;
	my @results = $invocant->search({}, {});

	return @results;
}

sub promote {
	my $invocant = $_[0];
	my $class = ref($invocant) || $invocant;

	my $new = bless $_[1], $class;
	$_[1] = $new;
	return $_[1];
}

sub atomic {
	my $invocant = shift;
	return ConvoTreeEngine::Mysql->atomic(@_);
}

1;