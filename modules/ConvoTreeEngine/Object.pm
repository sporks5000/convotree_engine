package ConvoTreeEngine::Object;

use strict;
use warnings;

use ConvoTreeEngine::Config;
use ConvoTreeEngine::Mysql;

sub _table {
	my $self  = shift;
	my $table = shift;
	return $ConvoTreeEngine::Config::tablePrefix . $table;
}

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

{
	my %describes;
	my %primary_keys;
	sub _describe {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $describes{$table} ||= do {
			my $describe = { map {$_->{Field} => $_} @{ $invocant->_mysql->fetchRows(qq/DESCRIBE $table;/) } };

			my @primary;
			foreach my $field (sort keys %$describe) {
				if (($describe->{$field}{Key} || '') eq 'PRI') {
					push @primary, $field;
				}
			}
			if (@primary) {
				$primary_keys{$table} = \@primary;
			}

			$describe;
		};
	}

	sub _primary_keys {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $primary_keys{$table} || do {
			$invocant->_describe();
			$primary_keys{$table};
		};

	}
}

sub create {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	my $self = $class->promote({});

	my $describe = $class->_describe;

	my $table = $class->_table;
	my (@fields, @values);
	foreach my $field (sort keys %$describe) {
		if (exists $args->{$field}) {
			push @fields, $field;
			if ($args->{$field} && ref $args->{$field} && $describe->{$field}{Type} eq 'json') {
				$args->{$field} = JSON::encode_json($args->{$field});
			}
			push @values, $args->{$field};
			$self->{$field} = delete $args->{$field};
		}
	}
	if (keys %$args) {
		ConvoTreeEngine::Exception::Input->throw(
			error => "Table '$table' does not have column(s) [" . join(', ', sort(keys %$args)) . ']',
		);
	}

	my $questionmarks = join ',', ('?') x @fields;
	my $fields = join ',', @fields;

	if ($describe->{id} && ($describe->{id}{Key} || '') eq 'PRI') {
		my $id = $class->_mysql->insertForId(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);

		$self->{id} = $id;
	}
	else {
		$class->_mysql->doQuery(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);
	}

	return $self;
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
	my $describe = $invocant->_describe;

	my $whereString;
	my @whereString;
	my @input;
	if ($args->{WHERE}) {
		$whereString = $args->{WHERE};
	}
	else {
		foreach my $field (keys %$args) {
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
	my $fields = join ', ', keys(%$describe);
	my $query = qq/
		SELECT $fields FROM $table
		$whereString
		$attrString
	/;
	my $rows = $invocant->_mysql->fetchRows($query, \@input);

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

sub _primary_key_where_clause {
	my $invocant = shift;

	my $table = $invocant->_table;
	my $primary_keys = $invocant->_primary_keys;
	die "Table '$table' does not have primary keys" unless $primary_keys && @$primary_keys;

	my @where;
	my @bits;
	foreach my $key (@$primary_keys) {
		push @where, "$key = ?";
		push @bits, $invocant->{$key};
	}
	my $where = join ' AND ', @where;

	return ($where, \@bits);
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my @ro = $self->_read_only_fields;
	foreach my $field (@ro) {
		if (exists $args->{$field}) {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$field' field cannot be updated on the '" . ref $self . "' object",
				args  => $args,
			) if (defined $args->{$field} xor defined $self->$field()) || (defined $args->{$field} && $args->{$field} ne $self->$field());
		}
	}

	my $describe = $self->_describe;

	my @sets;
	my @bits;
	foreach my $arg (keys %$args) {
		if ($describe->{$arg}) {
			push @sets, "$arg = ?";
			if ($args->{$arg} && ref $args->{$arg} && $describe->{$arg}{Type} eq 'json') {
				$args->{$arg} = JSON::encode_json($args->{$arg});
			}
			push @bits, $args->{$arg};
		}
		else {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$arg' field does not exist on the '" . ref $self . "' object",
				args  => $args,
			);
		}
	}
	my $sets = join ', ', @sets;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;
	push @bits, @$pk_bits;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/UPDATE $table SET $sets WHERE $where;/,
		\@bits,
	);

	return $self->refresh;
}

sub delete {
	my $self = shift;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/DELETE FROM $table WHERE $where;/,
		$pk_bits,
	);

	return;
}

sub refresh {
	my $self = shift;

	my $table    = $self->_table;
	my $describe = $self->_describe;
	my $fields   = join ', ', keys(%$describe);
	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $query = qq/SELECT $fields FROM $table WHERE $where;/;
	my $rows = $self->_mysql->fetchRows($query, $pk_bits);
	if (@$rows) {
		my $found = $rows->[0];
		%$self = %$found;
	}

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

sub asHashRef {
	my $self = shift;
	my $describe = $self->_describe();

	my $hash = {};
	foreach my $field (keys %$describe) {
		my $val = $self->{$field};
		if ($val && $describe->{$field}{Type} eq 'json') {
			$hash->{$field} = JSON::decode_json($val);
		}
		else {
			$hash->{$field} = $val;
		}
	}

	return $hash;
}

sub atomic {
	my $invocant = shift;
	return $invocant->_mysql->atomic(@_);
}

sub _mysql {
	return 'ConvoTreeEngine::Mysql';
}

1;