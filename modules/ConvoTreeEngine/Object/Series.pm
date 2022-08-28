package ConvoTreeEngine::Object::Series;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Object::Element;
use ConvoTreeEngine::Object::Series::ToElement;

sub _table {
	return shift->SUPER::_table('element_series');
}

sub _fields {
	my @fields = qw(id name category);
	return @fields if wantarray;
	return join ', ', @fields;
}

sub _read_only_fields {
	my @fields = qw(id);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

sub id {
	return shift->{id};
}

sub name {
	return shift->{name};
}

sub category {
	return shift->{category};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	ConvoTreeEngine::Exception::Input->throw(
		error => 'A Series requires a sequence',
		code  => 400,
	) unless $args->{sequence} && (ref $args->{sequence} || '') eq 'ARRAY';

	my $table = $invocant->_table;
	my $self;
	$invocant->atomic(sub {
		my $id = ConvoTreeEngine::Mysql->insertForId(
			qq/INSERT INTO $table (name, category) VALUES(?, ?);/,
			[$args->{name}, $args->{category}],
		);

		$self = $invocant->promote({
			id       => $id,
			name     => $args->{name},
			category => $args->{category},
		});

		$self->createParts(@{$args->{sequence}});
	});

	return $self;
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my $sequence = delete $args->{sequence};
	if (defined $sequence) {
		ConvoTreeEngine::Exception::Input->throw(
			error => 'A sequence must be an array',
			code  => 400,
		) unless (ref $sequence || '') eq 'ARRAY';
	}

	$self->atomic(sub {
		$self->SUPER::update($args);

		if ($sequence) {
			$self->deleteParts;
			$self->createParts(@$sequence);
		}
	});

	return $self->refresh;
}

### Uses "search" and "delete" from the base class

#===================#
#== Other Methods ==#
#===================#

sub deleteParts {
	my $self = shift;

	my $table = ConvoTreeEngine::Object::Series::ToElement->_table;
	ConvoTreeEngine::Mysql->doQuery(
		qq/DELETE FROM $table WHERE series_id = ?;/,
		[$self->id],
	);
}

sub createParts {
	my $self = shift;
	my @parts = @_;

	my %elements;
	my %series;

	my $sequence = 0;
	foreach my $part (@parts) {
		$sequence++;

		my $ref = ref $part || '';
		if (!$ref) {
			if ($part =~ m/^series([0-9]+)\z/i) {
				my $series_id = $1;
				$ref = 'ConvoTreeEngine::Object::Series';
				$part = $ref->findOrDie({id => $series_id});
			}
			elsif ($part =~ m/^[0-9]+\z/) {
				$ref = 'ConvoTreeEngine::Object::Element';
				$part = $ref->findOrDie({id => $part});
			}
			else {
				ConvoTreeEngine::Exception::Input->throw(
					error => 'Validation for Series sequence did not pass',
					code  => 400,
				);
			}
		}

		my @pieces;
		if ($ref eq 'ConvoTreeEngine::Object::Series') {
			$series{$part->id} = {
				series_id        => $self->id,
				element_id       => undef,
				nested_series_id => $part->id,
				sequence         => $sequence,
			};
		}
		else {
			$elements{$part->id} = {
				series_id        => $self->id,
				element_id       => $part->id,
				nested_series_id => undef,
				sequence         => $sequence,
			};
			my $paths = $part->elementPaths;
			foreach my $path (values %$paths) {
				push @pieces, ConvoTreeEngine::Object::Series::ToElement->search({series_id => $path->series_id});
			}

			foreach my $piece (@pieces) {
				$series{$piece->id} ||= {
					series_id        => $self->id,
					element_id       => $piece->id,
					nested_series_id => undef,
					sequence         => undef,
				};
			}
		}
	}

	return ConvoTreeEngine::Object::Series::ToElement->createMany(values(%elements), values(%series))
}

sub sequence {
	my $self = shift;

	my $ste_table = ConvoTreeEngine::Object::Series::ToElement->_table;
	my $e_table   = ConvoTreeEngine::Object::Element->_table;
	my $s_table   = $self->_table;

	my $query = qq/
		SELECT ste.series_id AS ste_series_id, ste.element_id AS ste_element_id, ste.nested_series_id AS ste_nested_series_id, ste.sequence AS ste_sequence,
			e.id AS e_id, e.type AS e_type, e.name AS e_name, e.category AS e_category, e.json AS e_json,
			s.id AS s_id, s.name AS s_name, s.category AS s_category,
			ste2.series_id AS ste2_series_id, ste2.element_id AS ste2_element_id, ste2.nested_series_id AS ste2_nested_series_id, ste2.sequence AS set2_sequence,
			e2.id AS e2_id, e2.type AS e2_type, e2.name AS e2_name, e2.category AS e2_category, e2.json AS e2_json
		FROM $ste_table ste
		LEFT JOIN $e_table e ON ste.element_id = e.id
		LEFT JOIN $s_table s ON ste.nested_series_id = s.id
		LEFT JOIN $ste_table ste2 on s.id = ste2.series_id
		LEFT JOIN $e_table e2 ON ste2.element_id = e2.id
		WHERE ste.series_id = ?
		ORDER BY ste.sequence, ste2.sequence;
	/;

	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, [$self->id]);

	##### TODO: what ever this is
}

#===========================#
#== Returning Information ==#
#===========================#

sub asHashRef {
	my $self = shift;
	return {
		id       => $self->id,
		name     => $self->name,
		category => $self->category,
	};
}

1;