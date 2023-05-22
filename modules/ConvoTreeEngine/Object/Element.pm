package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Validation;

sub _table {
	return shift->SUPER::_table('element');
}

sub _read_only_fields {
	my @fields = qw(id type);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

__PACKAGE__->createAccessors(qw/id type name category namecat json/);
__PACKAGE__->createRelationships(
	{
		name   => 'nestedObjs',
		class  => 'ConvoTreeEngine::Object::Element::Nested',
		fields => {element_id => 'id'},
		many   => 1,
	},
	{
		name   => 'parentNestedObjs',
		class  => 'ConvoTreeEngine::Object::Element::Nested',
		fields => {nested_element_id => 'id'},
		many   => 1,
	},
	{
		name   => 'nestedElements',
		class  => 'ConvoTreeEngine::Object::Element',
		fields => {id => sub {
			my $self = shift;
			return map {$_->nested_element_id} $self->nestedObjs;
		}},
		many   => 1,
	},
	{
		name   => 'parentElements',
		class  => 'ConvoTreeEngine::Object::Element',
		fields => {id => sub {
			my $self = shift;
			return map {$_->element_id} $self->parentNestedObjs;
		}},
		many   => 1,
	},
);

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	$args->{json} = ConvoTreeEngine::Validation->validateElementJson($args->{json}, $args->{type});

	$invocant->_confirm_namecat($args);

	my $table = $invocant->_table;
	my $self;
	$invocant->atomic(sub {
		$self = $invocant->SUPER::create($args);

		$self->doNestedElements;
	});

	return $self;
}

=head2 find

Allows passing in either an ID, a namecat, or standard find args.

=cut

sub find {
	my $invocant = shift;
	if (@_ == 1 && !ref $_[0]) {
		my $arg = shift;
		if ($arg =~ m/^[0-9]+$/) {
			return $invocant->SUPER::find({id => $arg});
		}
		else {
			return $invocant->SUPER::find({namecat => $arg});
		}
	}

	return $invocant->SUPER::find(@_);
}

sub findOrCreate {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	if ($args->{id}) {
		my $self = $invocant->find({id => $args->{id}});
		return $self if $self;
	}
	$invocant->_confirm_namecat($args);
	if ($args->{namecat}) {
		my $self = $invocant->find({namecat => $args->{namecat}});
		return $self if $self;
	}

	return $invocant->create($args);
}

sub createOrUpdate {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	my $self;
	if ($args->{id}) {
		$self = $invocant->find({id => $args->{id}});
	}
	else {
		$invocant->_confirm_namecat($args);
		if ($args->{namecat}) {
			$self = $invocant->find({namecat => $args->{namecat}});
		}
	}

	if ($self) {
		return $self->update($args);
	}

	return $invocant->create($args);
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my $skip_nested = delete $args->{skip_nested};
	if (exists $args->{json}) {
		$args->{json} = ConvoTreeEngine::Validation->validateElementJson($args->{json}, $self->type);
	}
	else {
		$skip_nested = 1;
	}

	$self->_confirm_namecat($args);

	$self->atomic(sub {
		if (($self->namecat xor $args->{namecat}) || $self->namecat ne $args->{namecat}) {
			$self->sanitizeNesting({namecat => $args->{namecat}});
		}
		$self->clearNestedElements unless $skip_nested;
		$self = $self->SUPER::update($args);
		$self->doNestedElements unless $skip_nested;
	});

	return $self;
}

sub delete {
	my $self = shift;

	my $response;
	$self->atomic(sub {
		$self->sanitizeNesting({remove => 1});
		$response = $self->SUPER::delete;
	});

	return $response;
}

### Uses "search" from the base class

sub searchWithNested {
	my $invocant = shift;
	my $id       = shift;

	my @ids;
	if ((ref $id || '') eq 'ARRAY') {
		@ids = @$id;
	}
	else {
		@ids = ($id, @_);
	}

	my $id_string;
	my @id_bits;
	my $namecat_string;
	my @namecat_bits;
	foreach my $id (@ids) {
		if ($id =~ m/^[0-9]+\z/) {
			$id_string .= '?,';
			push @id_bits, $id;
		}
		else {
			$namecat_string .= '?,';
			push @namecat_bits, $id;
		}
	}
	$id_string = substr($id_string, 0, -1) if $id_string;
	$namecat_string = substr($namecat_string, 0, -1) if $namecat_string;

	require ConvoTreeEngine::Object::Element::Nested;
	my $e_table  = $invocant->_table;
	my $ne_table = ConvoTreeEngine::Object::Element::Nested->_table;
	my $query = qq/
		SELECT e.id AS e_id, e.type AS e_type, e.name AS e_name, e.category AS e_category, e.namecat AS e_namecat, e.json AS e_json,
			ne.element_id, ne.nested_element_id,
			e2.id AS e2_id, e2.type AS e2_type, e2.name AS e2_name, e2.category AS e2_category, e2.namecat AS e2_namecat, e2.json AS e2_json
		FROM $e_table e
		LEFT JOIN $ne_table ne ON e.id = ne.element_id
		LEFT JOIN $e_table e2 ON ne.nested_element_id = e2.id
		WHERE
	/;
	if (@id_bits) {
		$query .= " e.id IN ($id_string)";
		if (@namecat_bits) {
			$query .= " OR";
		}
	}
	if (@namecat_bits) {
		$query .= " e.namecat IN ($namecat_string)";
	}

	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, [@id_bits, @namecat_bits]);

	my %elements;
	foreach my $row (@$rows) {
		$elements{$row->{e_id}} ||= $invocant->promote({
			id       => $row->{e_id},
			type     => $row->{e_type},
			name     => $row->{e_name},
			category => $row->{e_category},
			namecat  => $row->{e_namecat},
			json     => $row->{e_json},
		});
		$elements{$row->{e2_id}} ||= $invocant->promote({
			id       => $row->{e2_id},
			type     => $row->{e2_type},
			name     => $row->{e2_name},
			category => $row->{e2_category},
			namecat  => $row->{e2_namecat},
			json     => $row->{e2_json},
		}) if $row->{e2_id};
	}

	return values %elements if wantarray;
	return \%elements;
}

sub searchWithNested_hashRefs {
	my $invocant = shift;
	my $elements = $invocant->searchWithNested(@_);

	foreach my $id (keys %$elements) {
		$elements->{$id} = $elements->{$id}->asHashRef;
	}

	return values %$elements if wantarray;
	return $elements;
}

#===================#
#== Other Methods ==#
#===================#

sub _confirm_namecat {
	my $invocant = shift;
	my $args     = shift;

	foreach my $key (qw/name category/) {
		if (ref $invocant) {
			$args->{$key} //= $invocant->$key();
		}
		else {
			$args->{$key} //= undef;
		}
		if (defined $args->{$key}) {
			my $validator = ConvoTreeEngine::Validation->new();
			my $isValid = $validator->validateValue($args->{$key}, 'dashWords');
			unless ($isValid) {
				my $failures = $validator->listFailures;
				ConvoTreeEngine::Exception::Input->throw(
					error => "Validation for Element $key did not pass:\n$failures",
					code  => 400,
				);
			}
		}
	}

	if (defined $args->{name} || defined $args->{category}) {
		$args->{namecat} = ($args->{category} // '') . ":" . ($args->{name} // '');
	}
	else {
		$args->{namecat} = undef;
	}

	return;
}

sub listReferencedElements {
	my $self          = shift;
	my $args          = $self->_prep_args(@_);

	my $jsonRef = $self->jsonRef;
	my $type    = $self->type;

	my @elements;
	if ($type eq 'if') {
		foreach my $cond (@{$jsonRef->{cond}}) {
			if (@$cond > 1) {
				if (ref $cond->[1]) {
					push @elements, @{$cond->[1]};
				}
				else {
					push @elements, $cond->[1];
				}
			}
		}
	}
	elsif ($type eq 'choice') {
		foreach my $choice (@{$jsonRef->{choices}}) {
			if (exists $choice->{then}) {
				if (ref $choice->{then}) {
					push @elements, @{$choice->{then}};
				}
				else {
					push @elements, $choice->{then};
				}
			}
			push @elements, $choice->{element};
		}
	}
	elsif ($type eq 'elements') {
		if (ref $jsonRef->{get}) {
			push @elements, @{$jsonRef->{get}};
		}
		else {
			push @elements, $jsonRef->{get};
		}

		if (ref $jsonRef->{queue}) {
			push @elements, @{$jsonRef->{queue}};
		}
		else {
			push @elements, $jsonRef->{get};
		}
	}
	elsif ($type eq 'random') {
		foreach my $path (@{$jsonRef->{paths}}) {
			if (ref $path->[1]) {
				push @elements, @{$path->[1]};
			}
			else {
				push @elements, $path->[1];
			}
		}
	}

	my %element_ids;
	my %element_namecats;
	foreach my $element (@elements) {
		if ($element =~ m/^[0-9]+\z/) {
			$element_ids{$element} = 1;
		}
		else {
			$element_namecats{$element} = 1;
		}
	}

	@elements = ();
	my %verified;
	foreach my $namecat (keys %element_namecats) {
		my $element = ConvoTreeEngine::Object::Element->findOrDie({namecat => $namecat});
		my $id = $element->id;
		push @elements, $id;
		$verified{$id} = 1;
	}

	foreach my $id (keys %element_ids) {
		push @elements, $id;
		if ($args->{verify_exists} && !$verified{$id}) {
			ConvoTreeEngine::Object::Element->findOrDie({id => $id});
		}
	}

	return @elements;
}

sub doNestedElements {
	my $self = shift;

	if (my @elements = $self->listReferencedElements({verify_exists => 1})) {
		my $type = $self->type;
		if ($type eq 'if' || $type eq 'choice' || $type eq 'elements' || $type eq 'random') {
			my $my_id = $self->id;
			require ConvoTreeEngine::Object::Element::Nested;
			my $table = ConvoTreeEngine::Object::Element::Nested->_table();
			my $query = qq/INSERT INTO $table (element_id, nested_element_id) VALUES/;
			my @bits;

			foreach my $id (@elements) {
				push @bits, $my_id, $id;
				$query .= '(?,?),'
			}

			$query = substr($query, 0, -1);
			ConvoTreeEngine::Mysql->doQuery($query, \@bits);
		}
	}

	return;
}

sub clearNestedElements {
	my $self = shift;

	require ConvoTreeEngine::Object::Element::Nested;
	my $table = ConvoTreeEngine::Object::Element::Nested->_table();
	ConvoTreeEngine::Mysql->doQuery(qq/
		DELETE FROM $table WHERE element_id = ?;
	/, [$self->id]);

	return;
}

sub sanitizeNesting {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my $id = $self->id;

	require ConvoTreeEngine::Object::Element::Nested;
	my $e_table  = $self->_table;
	my $ne_table = ConvoTreeEngine::Object::Element::Nested->_table;
	my $rows = ConvoTreeEngine::Mysql->fetchRows(qq/
		SELECT e.id, e.type, e.name, e.category, e.namecat, e.json FROM $ne_table ne
		JOIN $e_table e ON ne.element_id = e.id
		WHERE ne.nested_element_id = ?;
	/, [$id]);

	return unless @$rows;
	$args->{id} = $id;

	foreach my $row (@$rows) {
		my $type    = $row->{type};
		my $element = $self->promote($row);
		my $jsonRef = $element->jsonRef;

		if ($type eq 'if') {
			foreach my $cond (@{$jsonRef->{cond}}) {
				if (@$cond > 1) {
					$cond->[1] = $element->_sanitize_nesting_arrays($cond->[1], $args);
				}
			}
		}
		elsif ($type eq 'choice') {
			foreach my $choice (@{$jsonRef->{choices}}) {
				ConvoTreeEngine::Exception::Internal->throw(
					error => "Cannot delete element with ID $args->{id}, as it is a choice in element " . $element->id . '.',
					code  => 500,
				) if $choice->{element} == $args->{id};

				if (exists $choice->{then}) {
					$choice->{then} = $element->_sanitize_nesting_arrays($choice->{then}, $args);
				}
			}
		}
		elsif ($type eq 'elements') {
			$jsonRef->{queue} = $element->_sanitize_nesting_arrays($jsonRef->{queue}, $args);
			$jsonRef->{get} = $element->_sanitize_nesting_arrays($jsonRef->{get}, $args);
		}
		elsif ($type eq 'random') {
			foreach my $path (@{$jsonRef->{paths}}) {
				$path->[1] = $element->_sanitize_nesting_arrays($path->[1], $args);
			}
		}

		$element->update({json => $jsonRef, skip_nested => 1});
	}

	if ($args->{remove}) {
		ConvoTreeEngine::Mysql->doQuery(qq/
			DELETE FROM $ne_table
			WHERE nested_element_id = ?;
		/, [$id]);
	}

	return;
}

sub _sanitize_nesting_arrays {
	my $self         = shift;
	my $nestingBlock = shift;
	my $args         = shift;

	my $id          = $args->{id};
	my $old_namecat = $self->namecat   || '';
	my $new_namecat = $args->{namecat} || $id;
	my $remove      = $args->{remove};

	my @elements;
	if (ref $nestingBlock) {
		foreach my $ident (@$nestingBlock) {
			if ($ident eq $id || $ident eq $old_namecat) {
				unless ($remove) {
					push @elements, $new_namecat;
				}
			}
			else {
				push @elements, $ident;
			};
		}
	}
	else {
		if ($nestingBlock eq $id || $nestingBlock eq $old_namecat) {
			unless ($remove) {
				push @elements, $new_namecat;
			}
		}
		else {
			push @elements, $nestingBlock;
		};
	}

	return $elements[0] if scalar(@elements) == 1;
	return \@elements;
}

#===========================#
#== Returning Information ==#
#===========================#

sub jsonRef {
	return JSON::decode_json(shift->json);
}

sub asHashRef {
	my $self = shift;

	my $hash = $self->SUPER::asHashRef;
	$hash->{json} = $self->jsonRef;

	return $hash;
}

1;