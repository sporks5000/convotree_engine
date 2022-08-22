package ConvoTreeEngine::Object::ElementPath;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Object::Element;
use ConvoTreeEngine::Object::Series;

sub _table {
	return 'element_path';
}

sub _fields {
	my @fields = qw(id element_id series_id);
	return @fields if wantarray;
	return join ', ', @fields;
}

sub _read_only_fields {
	my @fields = qw(id element_id series_id);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

sub id {
	return shift->{id};
}

sub element_id {
	return shift->{element_id};
}

sub series_id {
	return shift->{series_id};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	### Make sure that the specified element and series exist
	ConvoTreeEngine::Object::Element->findOrDie({id => $args->{element_id}});
	ConvoTreeEngine::Object::Series->findOrDie({id => $args->{series_id}});

	my $table = $invocant->_table;
	my $id = ConvoTreeEngine::Mysql->insertForId(
		qq/INSERT INTO $table (element_id, series_id) VALUES(?, ?);/,
		[$args->{element_id}, $args->{series_id}],
	);

	my $self = $invocant->promote({
		id         => $id,
		element_id => $args->{element_id},
		series_id  => $args->{series_id},
	});

	return $self;
}

### Uses "search", "update", and "delete" from the base class

#===================#
#== Other Methods ==#
#===================#

sub series {
	my $self = shift;
	return ConvoTreeEngine::Object::Series->find({id => $self->series_id});
}

#===========================#
#== Returning Information ==#
#===========================#

sub asHashRef {
	my $self = shift;

	return {
		id         => $self->id,
		element_id => $self->element_id,
		series_id  => $self->series_id,
	};
}

1;