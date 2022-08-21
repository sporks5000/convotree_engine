package ConvoTreeEngine::Object::Series;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Object::Element;

=pod
sub _table {
	return 'element';
}
=cut

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

sub sequence {
	return shift->{sequence};
}

sub elements {
	my $self = shift;
	$self->{elements} || do {
		my $full = $self->find({id => $self->id});
		%$self = %$full;
	}
	return $self->{elements};
}

sub series {
	my $self = shift;
	$self->{sequence} || do {
		my $full = $self->find({id => $self->id});
		%$self = %$full;
	}
	return $self->{sequence};
}

#==========#
#== CRUD ==#
#==========#

=pod
sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	$args->{json} = $invocant->_validate_json($args->{json}, $args->{type});
	$args->{name} //= undef;
	$args->{category} //= undef;

	my $table = $invocant->_table;
	my $id = ConvoTreeEngine::Mysql->insertForId(
		qq/INSERT INTO $table (type, name, category, json) VALUES(?, ?, ?, ?);/,
		[$args->{type}, $args->{name}, $args->{category}, $args->{json}],
	);

	return $invocant->promote({
		id       => $id,
		type     => $args->{type},
		name     => $args->{name},
		category => $args->{category},
		json     => $args->{json},
	});
}
=cut

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $just_rows = delete $attrs->{just_rows};

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
				my $string .= "$field IN (" . join(',', ('?') x @{$args->{$field}}) . ')';
				push @whereString, $string;
				push @input, @{$args->{$field}};
			}
			elsif ($ref eq 'HASH' && scalar(keys %{$args->{$field}}) == 1) {
				my ($key) = keys %{$args->{$field}};
				my $value = $args->{$field}{$key};
				push @whereString, "$field $key ?";
				push @input, $value;
			}
			else {
				push @whereString, "$field = ?";
				push @input, $args->{$field};
			}
		}
	}

	$whereString ||= join ' AND ', @whereString;
	$whereString = "WHERE $whereString" if $whereString;
	my $query = qq/
		SELECT
			element_series.id, element_series.name, element_series.category,
			series_to_element.nested_series_id, series_to_element.element_id, series_to_element.sequence,
		FROM element_series
		JOIN series_to_element
			ON element_series.id = series_to_element.series_id
		$whereString
		ORDER BY element_series.id ASC, series_to_element.sequence ASC
	/;
	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, \@input);
	return $rows if $just_rows;

	my @assembled = $invocant->assembleFromRows($rows);

	##### TODO: Order by? Other things commonly asked for within $attrs?

	return @assembled;
}

=head2 assembleFromRows

Assemble the series object based on rows returned from the search.

This potentially results in two assembly stages - an outer stage and an inner stage. During the
outer stage, we determine if there are any nested series that we need to pull additional information
for. If there are, we move into the inner stage, performing another search in order to get the data
for those and then assembling "shallow" copies of them. We return those copies along with a hash of
the element IDs contained within them.

The outer stage resumes with us searching for all of the associated elements from both the inner and
outer stages. Then we assemble "deep" copies of each series and return these as an array.

There is no limit to how deep series nesting might go, nor is there a limitation prevending nesting
a series within itself, so there is no guarantee that this will get EVERYTHING, but it should at
least give a buffer before the next data request is needed.

=cut

sub assembleFromRows {
	my $class = shift;
	my $rows  = shift;
	my $deep  = shift // 1;

	my %series;
	my %series_needed;
	my %elements;
	foreach my $row (@$rows) {
		$series{$row->{id}} ||= bless {
			id       => $row->{id},
			name     => $row->{name},
			category => $row->{category},
			sequence => [],
			elements => {},
			series   => {},
		}, 'ConvoTreeEngine::Object::Series';

		my $string;
		if ($row->{nested_series_id}) {
			$series_needed{$row->{nested_series_id}} ||= undef;
			$string = 'SERIES' . $row->{nested_series_id};
			$series{$row->{id}}{series}{$row->{nested_series_id}} = undef;
		}
		elsif ($row->{element_id}) {
			$elements{$row->{element_id}} ||= undef;
			$string = $row->{element_id};
			$series{$row->{id}}{elements}{$row->{element_id}} = undef;
		}

		if ($row->{sequence}) {
			push @{$series{$row->{id}}{sequence}}, [
				$row->{sequence},
				$string,
			];
		}
	}

	my $assembled = {};
	if ($deep) {
		my $moreElements = {};
		if (%series_needed) {
			$rows = $class->search({id => [keys %series_needed]}, {just_rows => 1});
			($assembled, $moreElements) = $class->assembleFromRows($rows, 0); ### Shallow assemble
		}

		%elements = (
			%elements,
			%$moreElements,
		);

		my @elements = ConvoTreeEngine::Object::Element->search({id => [keys %elements]});
		%elements = map {$_->id => $_} @elements;
	}

	foreach my $id (keys %series) {
		my $series = $series{$id};
		@{$series->{sequence}} = map {$_->[1]} sort {$a->[0] <=> $b->[0]} @{$series->{sequence}};
	}

	foreach my $id (keys %series) {
		my $series = $series{$id};
		if ($deep) {
			foreach my $element_id (keys %{$series->{elements}}) {
				$series->{elements}{$element_id} = $elements{$element_id};
			}
		}

		foreach my $series_id (keys %{$series->{series}}) {
			my $seriesDeep = $series{$series_id} || $assembled->{$series_id};
			unless ($seriesDeep) {
				delete $series->{series}{$series_id};
				next;
			}

			$series->{series}{$series_id} = bless {
				id       => $seriesDeep->{id},
				name     => $seriesDeep->{name},
				category => $seriesDeep->{category},
				sequence => $seriesDeep->{sequence},
			}, 'ConvoTreeEngine::Object::Series';

			if ($deep) {
				foreach my $element_id (keys %{$seriesDeep->{elements}}) {
					$series->{elements}{$element_id} ||= $elements{$element_id} if $elements{$element_id};
				}
				foreach my $nested_series_id (keys %{$seriesDeep->{series}}) {
					my $seriesDeeper = $series{$nested_series_id} || $assembled->{$nested_series_id};
					next unless $seriesDeeper;

					$series->{series}{$nested_series_id} = {
						id       => $seriesDeeper->{id},
						name     => $seriesDeeper->{name},
						category => $seriesDeeper->{category},
						sequence => $seriesDeeper->{sequence},
					}, 'ConvoTreeEngine::Object::Series';
				}
			}
		}
	}

	return values %series if $deep;
	return \%series, \%elements;
}

=pod

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	$args->{json} = $self->_validate_json($args->{json}, $self->type) if exists $args->{json};

	my @sets;
	my @bits;
	foreach my $arg (keys %$args) {
		ConvoTreeEngine::Exception::Input->throw(
			error => "Only the 'json' field can be updated on the 'Element' object",
			args  => $args,
		) if $arg ne 'name' && $arg ne 'json' && $arg ne 'category';
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
=cut

#===========================#
#== Returning Information ==#
#===========================#

sub elementsAsHashRefs {
	my $self = shift;
	my %elements = %{$self->elements};
	%elements = map {$_ => $elements{$_}->asHashRef} keys %elements;
	return \%elements;
}

sub seriesAsHashRefs {
	my $self = shift;
	my %series = %{$self->series};
	%series = map {$_ => $series{$_}->asHashRef} keys %series;
	return \%series;
}

sub asHashRef {
	my $self = shift;
	return {
		id       => $self->id,
		name     => $self->name,
		category => $self->category,
		sequence => $self->sequence,
	};
}

1;