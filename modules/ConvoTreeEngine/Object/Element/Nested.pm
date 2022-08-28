package ConvoTreeEngine::Object::Element::Nested;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

sub _table {
	return shift->SUPER::_table('nested_element');
}

sub _fields {
	my @fields = qw(element_id nested_element_id);
	return @fields if wantarray;
	return join ', ', @fields;
}

sub _read_only_fields {
	my @fields = qw(element_id nested_element_id);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

sub element_id {
	return shift->{element_id};
}

sub nested_element_id {
	return shift->{nested_element_id};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	my $table = $invocant->_table;
	my $self;
	ConvoTreeEngine::Mysql->doQuery(
		qq/INSERT INTO $table (element_id, nested_element_id) VALUES(?, ?);/,
		[$args->{element_id}, $args->{nested_element_id}],
	);

	$self = $invocant->promote({
		element_id        => $args->{element_id},
		nested_element_id => $args->{nested_element_id},
	});

	return $self;
}

sub search {
	##### TODO: This
}

sub update {
	my $self = shift;

	##### TODO: Throw an exception
}

sub delete {
	##### TODO: This
}


#===========================#
#== Returning Information ==#
#===========================#

sub asHashRef {
	my $self = shift;

	return {
		element_id        => $self->element_id,
		nested_element_id => $self->nested_element_id,
	}
}

1;