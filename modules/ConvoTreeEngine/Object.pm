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
	my $class = ref($invocant) || $invocant;

	ConvoTreeEngine::Exception::Internal->throw(
		error => "Class '$class' does not have a defined search method",
	)
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

1;