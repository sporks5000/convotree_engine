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
			elsif ($part =~ m/^[0-9]+\s/) {
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
			@pieces = ConvoTreeEngine::Object::Series::ToElement->search({series_id => $part->id});
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
		}

		foreach my $piece (@pieces) {
			if ($piece->isElement) {
				$elements{$piece->id} ||= {
					series_id        => $self->id,
					element_id       => undef,
					nested_series_id => $piece->id,
					sequence         => undef,
				};
			}
			else {
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