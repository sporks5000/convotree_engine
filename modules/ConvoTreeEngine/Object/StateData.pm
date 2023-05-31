package ConvoTreeEngine::Object::StateData;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Validation;

sub _table {
	return shift->SUPER::_table('state_data');
}

sub _read_only_fields {
	my @fields = qw(id app_uuid user_uuid);
	return @fields if wantarray;
	return join ', ', @fields;
}

__PACKAGE__->createAccessors(qw/id app_uuid user_uuid data/);

#==========#
#== CRUD ==#
#==========#

sub create {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	$args = $class->validate_uuids($args);

	return $class->SUPER::create($args);
}

sub createOrUpdate {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	$args = $class->validate_uuids($args);

	my $self;
	if ($args->{id}) {
		$self = $class->find({id => $args->{id}});
	}
	else {
		$self = $class->find({app_uuid => $args->{app_uuid}, user_uuid => $args->{user_uuid}});
	}

	if ($self) {
		return $self->update($args);
	}

	return $class->create($args);
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	foreach my $field (qw/app_uuid user_uuid/) {
		### These cannot change, so no point in passing them
		delete $args->{$field};
	}

	$self = $self->SUPER::update($args);

	return $self;
}

sub search {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	$args = $class->validate_uuids($args);

	return $class->SUPER::search($args);
}

=head2 validate_uuids

Ensure that the uuid fields regex match uuids, and are lowercase.

=cut

sub validate_uuids {
	my $invocant = shift;
	my $args     = shift;

	foreach my $field (qw/app_uuid user_uuid/) {
		next unless exists $args->{$field};

		$args->{$field} = lc $args->{$field};

		my $validator = ConvoTreeEngine::Validation->new();
		my $isValid = $validator->validateValue($args->{$field}, 'uuid');
		unless ($isValid) {
			my $failures = $validator->listFailures;
			ConvoTreeEngine::Exception::Input->throw(
				error => "Validation for $field did not pass:\n$failures",
				code  => 400,
			);
		}
	}

	return $args;
}

#===========================#
#== Returning Information ==#
#===========================#

sub dataRef {
	return JSON::decode_json(shift->data);
}

sub asHashRef {
	my $self = shift;

	my $hash = $self->SUPER::asHashRef;
	$hash->{data} = $self->dataRef;

	return $hash;
}

1;