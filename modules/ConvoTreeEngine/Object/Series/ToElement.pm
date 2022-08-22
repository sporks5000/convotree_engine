package ConvoTreeEngine::Object::Series::ToElement;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Object::Element;
use ConvoTreeEngine::Object::Series;

sub _table {
	return 'series_to_element';
}

sub _fields {
	my @fields = qw(series_id element_id nested_series_id sequence);
	return @fields if wantarray;
	return join ', ', @fields;
}

sub _read_only_fields {
	my @fields = qw(series_id element_id nested_series_id sequence);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

sub series_id {
	return shift->{series_id};
}

sub element_id {
	return shift->{element_id};
}

sub nested_series_id {
	return shift->{nested_series_id};
}

sub sequence {
	return shift->{sequence};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	### Make sure that the specified element and series exist
	ConvoTreeEngine::Object::Element->findOrDie({id => $args->{element_id}}) if $args->{element_id};
	ConvoTreeEngine::Object::Series->findOrDie({id => $args->{series_id}}) if $args->{series_id};

	my $table = $invocant->_table;
	my $fields = $invocant->_fields;
	ConvoTreeEngine::Mysql->doQuery(
		qq/INSERT INTO $table ($fields) VALUES(?, ?, ?, ?);/,
		[$args->{series_id}, $args->{element_id}, $args->{nested_series_id}, $args->{sequence}],
	);

	my $self = $invocant->promote({
		series_id        => $args->{series_id},
		element_id       => $args->{element_id},
		nested_series_id => $args->{nested_series_id},
		sequence         => $args->{sequence},
	});

	return $self;
}

sub createMany {
	my $invocant = shift;
	my @pieces   = @_;

	### Note that we do not check if the related element or series exists. This is to save time and hopefully will not bite us later.

	my @bits;
	my $string = '';
	foreach my $piece (@pieces) {
		$string .= '(?, ?, ?, ?),';
		push @bits, $piece->{series_id}, $piece->{element_id}, $piece->{nested_series_id}, $piece->{sequence};
	}
	$string = substr $string, 0, -1;

	my $table = $invocant->_table;
	my $fields = $invocant->_fields;
	ConvoTreeEngine::Mysql->doQuery(
		qq/INSERT INTO $table ($fields) VALUES $string;/,
		\@bits,
	);

	return;
}

sub delete {
	my $self = shift;

	my $whereString = 'series_id = ' . $self->series_id . 'AND ';
	if (my $element_id = $self->element_id) {
		$whereString .= "element_id = $element_id AND ";
	}
	else {
		$whereString .= "element_id IS NULL AND ";
	}
	if (my $nested_series_id = $self->nested_series_id) {
		$whereString .= "nested_series_id = $nested_series_id AND ";
	}
	else {
		$whereString .= "nested_series_id IS NULL AND ";
	}

	my $table = $self->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/DELETE FROM $table WHERE $whereString;/,
	);

	return;
}

### Uses "search" and "update" from the base class

#===================#
#== Other Methods ==#
#===================#

sub nestedObject {
	my $self = shift;

	return $self->{cache}{__nested_object} ||= do {
		if (my $eid = $self->element_id) {
			return ConvoTreeEngine::Object::Element->find({id => $eid});
		}
		else {
			return ConvoTreeEngine::Object::Element->series({id => $self->nested_series_id});
		}
	};
}

#===========================#
#== Returning Information ==#
#===========================#

sub isElement {
	my $self = shift;
	return $self->element_id ? 1 : 0;
}

sub isSeries {
	my $self = shift;
	return $self->nested_series_id ? 1 : 0;
}

sub asHashRef {
	my $self = shift;

	return {
		series_id        => $self->series_id,
		element_id       => $self->element_id,
		nested_series_id => $self->nested_series_id,
		sequence         => $self->sequence,
	};
}

1;