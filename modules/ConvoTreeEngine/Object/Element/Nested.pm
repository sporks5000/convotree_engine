package ConvoTreeEngine::Object::Element::Nested;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

sub _table {
	return shift->SUPER::_table('nested_element');
}

sub _read_only_fields {
	my @fields = qw(element_id nested_element_id);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

__PACKAGE__->createAccessors(qw/element_id nested_element_id/);

#==========#
#== CRUD ==#
#==========#

sub update {
	my $self = shift;

	ConvoTreeEngine::Exception::Internal->throw(
		error => 'Nested Elements cannot be updated',
	);
}

1;