package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

sub _table {
	return shift->SUPER::_table('element');
}

sub _fields {
	my @fields = qw(id type name category json);
	return @fields if wantarray;
	return join ', ', @fields;
}

sub _read_only_fields {
	my @fields = qw(id type);
	return @fields if wantarray;
	return join ', ', @fields;
}

#=====================#
#== Field Accessors ==#
#=====================#

sub id {
	return shift->{id};
}

sub type {
	return shift->{type};
}

sub name {
	return shift->{name};
}

sub category {
	return shift->{category};
}

sub json {
	return shift->{json};
}

#==========#
#== CRUD ==#
#==========#

sub create {
	my $invocant = shift;
	my $args     = $invocant->_prep_args(@_);

	$args->{json} = $invocant->_validate_json($args->{json}, $args->{type});
	$args->{name} //= undef;
	$args->{category} //= undef;

	my $table = $invocant->_table;
	my $self;
	$invocant->atomic(sub {
		my $id = ConvoTreeEngine::Mysql->insertForId(
			qq/INSERT INTO $table (type, name, category, json) VALUES(?, ?, ?, ?);/,
			[$args->{type}, $args->{name}, $args->{category}, $args->{json}],
		);

		$self = $invocant->promote({
			id       => $id,
			type     => $args->{type},
			name     => $args->{name},
			category => $args->{category},
			json     => $args->{json},
		});

		$self->doNestedElements;
	});

	return $self;
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my $skip_nested = delete $args->{skip_nested};
	if (exists $args->{json}) {
		$args->{json} = $self->_validate_json($args->{json}, $self->type);
	}
	else {
		$skip_nested = 1;
	}

	$self->atomic(sub {
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
		$self->sanitizeNesting;
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

	my $string;
	my @bits;
	foreach my $id (@ids) {
		$string .= '?,';
		push @bits, $id;
	}
	$string = substr($string, 0, -1);

	require ConvoTreeEngine::Object::Element::Nested;
	my $e_table  = $invocant->_table;
	my $ne_table = ConvoTreeEngine::Object::Element::Nested->_table;
	my $rows = ConvoTreeEngine::Mysql->fetchRows(qq/
		SELECT e.id AS e_id, e.type AS e_type, e.name AS e_name, e.category AS e_category, e.json AS e_json,
			ne.element_id, ne.nested_element_id,
			e2.id AS e2_id, e2.type AS e2_type, e2.name AS e2_name, e2.category AS e2_category, e2.json AS e2_json
		FROM $e_table e
		LEFT JOIN $ne_table ne ON e.id = ne.element_id
		LEFT JOIN $e_table e2 ON ne.nested_element_id = e2.id
		WHERE e.id IN ($string);
	/, \@bits);

	my %elements;
	foreach my $row (@$rows) {
		$elements{$row->{e_id}} ||= $invocant->promote({
			id       => $row->{e_id},
			type     => $row->{e_type},
			name     => $row->{e_name},
			category => $row->{e_category},
			json     => $row->{e_json},
		});
		$elements{$row->{e2_id}} ||= $invocant->promote({
			id       => $row->{e2_id},
			type     => $row->{e2_type},
			name     => $row->{e2_name},
			category => $row->{e2_category},
			json     => $row->{e2_json},
		});
	}

	return values %elements if wantarray;
	return \%elements;
}

#================#
#== Validation ==#
#================#

{
	my %typeValidation;

	my $ignore = sub {
		### no validation necessary; always returns true
		return 1;
	};
	my $undefined = sub {
		my ($class, $value) = @_;
		return 0 if defined $value;
		return 1;
	};
	my $boolean = sub {
		### Returns true if the value is strictly boolean
		my ($class, $value) = @_;
		return 1 if !defined $value;
		if (ref $value) {
			return 1 if $value->isa('JSON::Boolean');
			return 0;
		}
		return 1 if $value =~ /^[01]\z/;
		return 0;
	};
	my $hash = sub {
		my ($class, $value) = @_;
		return 0 unless (ref $value || '' ) eq 'HASH';
		return 1;
	};
	my $array = sub {
		my ($class, $value) = @_;
		return 0 unless (ref $value || '' ) eq 'ARRAY';
		return 1;
	};
	my $variableName = sub {
		### Returns true if the value matches what we expect from a javascript variable name
		my ($class, $value) = @_;
		return 0 unless defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^[a-zA-Z0-9_.]+\z/;
		return 1;
	};
	my $words = sub {
		### Returns true if the value is a string of words separated by either single spaces or single hyphens
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(?:[a-zA-Z0-9_]+[ -]?)+\b\z/;
		return 1;
	};
	my $word = sub {
		### Returns true if the value is a single word containg letters numbers and/or underscores
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^[a-zA-Z0-9_]+\z/;
		return 1;
	};
	my $string = sub {
		### returns true if the value is a text string (which may be empty)
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 1;
	};
	my $positiveInt = sub {
		### Returns true if the value looks like a positive integer
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^[1-9][0-9]*|0\z/;
		return 1;
	};
	my $number = sub {
		### Returns true if the value looks like a logical number, either positive or negative, with or without decimal places
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(-?[1-9][0-9]*|0)(\.[0-9]+)?\z/;
		return 1;
	},
	my $itemBlock = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will either be undefined or a string of words
		return 0 if defined $value->[0] && !$class->_validate_value($value->[0], 'words');
		### The second element must be undefined, or a string, or another item block
		if (defined $value->[1]) {
			return 0 unless $class->_validate_value($value->[1], ['string', 'arrayOf(itemBlock)']);
			### If it is defined, there cannot be a third element
			return 0 unless @$value == 2;
		}
		else {
			### If the second element is undefined, the third must match the validation for a variable name
			return 0 unless @$value == 3;
			return 0 unless $class->_validate_value($value->[2], 'variableName');
		}
		return 1;
	};
	my $singleElement = sub {
		### Return true if the valus has the structure of a single element
		my ($class, $value, $type) = @_;
		$type ||= $value->{type};
		return 0 unless $type;
		return 0 unless $typeValidation{$type};
		return 0 unless (ref $value || '') eq 'HASH';
		foreach my $key (keys %$value) {
			next if $key eq 'type';
			return 0 unless $typeValidation{$type}{$key};
		}
		foreach my $key (keys %{$typeValidation{$type}}) {
			next unless $typeValidation{$type}{$key}[0] && exists $value->{$key};
			return 0 if !exists $value->{$key};
			### Make sure it passes validation for that element type
			my @args = ($value->{$key}, $typeValidation{$type}{$key}[1]);
			push @args, $typeValidation{$type}{$key}[2] if scalar @{$typeValidation{$type}{$key}} > 2;
			return 0 unless $class->_validate_value(@args);
		}
		return 1;
	};
	my $conditionString = sub {
		### A string of text, potentially of multiple parts separated with and/or operators ('&' or '|')
		my ($class, $value) = @_;
		return 1 if !defined $value;
		return 0 if ref $value;
		return 0 if !length $value;
		my @parts = split m/\s*(&|\|)\s*/, $value;
		foreach my $part (@parts) {
			### Each part contains a variable name, an operator, and a condition
			my $operator = do {
				$part =~ m/([!><]=|[=><])/;
				$1;
			};
			return 0 unless $operator;
			my ($varName, $cond, @other) = split m/\s*$operator\s*/, $part;
			return 0 if @other;
			return 0 unless $class->_validate_value($varName, 'variableName');
			if ($operator =~ m/[<>]/) {
				### If the operator is specific to numbers, make sure that the condition is a number
				return 0 unless $class->_validate_value($cond, 'number');
			}
			else {
				### Otherwise the condition can be a single word
				return 0 unless $class->_validate_value($cond, 'word');
			}
		}
		return 1;
	};
	my $singleCondition = sub {
		### the value will be an array
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will either be undefined or a condition string
		return 0 if defined $value->[0] && !$class->_validate_value($value->[0], 'conditionString');
		return 0 if @$value > 2;
		return 1 unless @$value == 2;
		### If the second element is present, it should be an element ID or an array of element IDs
		return 0 unless $class->_validate_value($value->[1], ['arrayOf(positiveInt)', 'positiveInt']);
		return 1;
	};
	my $variableUpdates = sub {
		### Returns true if given a hash of variable names to strings (or undefineds)
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'hash');
		foreach my $key (keys %$value) {
			return 0 unless $class->_validate_value($key, 'variableName');
			return 0 unless $class->_validate_value($value->{$key}, ['string', 'undefined']);
			return 0 if $value->{$key} =~ m/^[+\*\/-]=/ && !$class->_validate_value(substr($value->{$key}, 2), 'number');
		}
		return 1;
	};
	my $choice = sub {
		my ($class, $value) = @_;
		return 0 unless defined $value;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will be a condition string
		return 0 unless $class->_validate_value($value->[0], 'conditionString');
		### The second element will be what we display for the choice
		return 0 unless $class->_validate_value($value->[1], 'string');
		next if @$value == 2;
		return 0 if @$value > 3;
		### If there is a third element, it should be an element ID or an array of element IDs
		return 0 unless $class->_validate_value($value->[2], ['arrayOf(positiveInt)', 'positiveInt']);
	};
	my $arrayOf = sub {
		my ($class, $value, @patterns) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		return 0 unless @patterns;
		foreach my $deep (@$value) {
			return 0 unless $class->_validate_value($deep, \@patterns);
		}
		return 1;
	};

	my %validations = (
		ignore          => $ignore,
		undefined       => $undefined,
		boolean         => $boolean,
		hash            => $hash,
		array           => $array,
		variableName    => $variableName,
		words           => $words,
		word            => $word,
		string          => $string,
		positiveInt     => $positiveInt,
		number          => $number,
		itemBlock       => $itemBlock,
		singleElement   => $singleElement,
		conditionString => $conditionString,
		singleCondition => $singleCondition,
		variableUpdates => $variableUpdates,
		choice          => $choice,
	);

	%typeValidation = (
		item     => {
			text   => [1, 'arrayOf(itemBlock)'],
			delay  => [0, 'positiveInt'],
			prompt => [0, 'boolean'],
			stop   => [0, 'boolean'],
			arbit  => [0, 'ignore'],
		},
		note     => {
			note  => [1, 'string'],
			arbit => [0, 'ignore'],
		},
		raw      => {
			html   => [1, 'string'],
			delay  => [0, 'positiveInt'],
			prompt => [0, 'boolean'],
			stop   => [0, 'boolean'],
			arbit  => [0, 'ignore'],
		},
		enter    => {
			start => [1, 'string'],
			end   => [1, 'string'],
			name  => [1, 'words'],
			arbit => [0, 'ignore'],
		},
		exit     => {
			name  => [1, ['undefined', 'words']],
			all   => [0, 'boolean'],
			arbit => [0, 'ignore'],
		},
		if       => {
			cond  => [1, 'arrayOf(singleCondition)'],
			arbit => [0, 'ignore'],
		},
		assess   => {
			cond  => [1, 'singleCondition'],
			arbit => [0, 'ignore'],
		},
		negate   => {
			assess_id => [1, ['arrayOf(positiveInt)', 'positiveInt']],
			arbit     => [0, 'ignore'],
		},
		stop     => {
			arbit     => [0, 'ignore'],
		},
		varaible => {
			update => [1, 'variableUpdates'],
			arbit  => [0, 'ignore'],
		},
		choice   => {
			choices => [1, 'arrayOf(choice)'],
			arbit   => [0, 'ignore'],
		},
		display  => {
			disp  => [1, 'hash'],
			delay => [0, 'positiveInt'],
			stop  => [0, 'boolean'],
			arbit => [0, 'ignore'],
		},
		do       => {
			function => [1, 'word'],
			args     => [0, 'array'],
			delay    => [0, 'positiveInt'],
			stop     => [0, 'boolean'],
			arbit    => [0, 'ignore'],

		},
		data     => {
			get   => [1, ['arrayOf(positiveInt)', 'positiveInt']],
			arbit => [0, 'ignore'],
		},
		series   => {
			series => [1, ['arrayOf(positiveInt)', 'positiveInt']],
			arbit  => [0, 'ignore'],
		},
	);

	sub _validate_json {
		my $invocant = shift;
		my $json     = shift;
		my $type     = shift;

		my $class = ref $invocant || $invocant;

		unless (ref $json) {
			$json = JSON::decode_json($json);
		}

		my $success = $class->_validate_value($json, $type, 'singleElement');
		unless ($success) {
			my $failures = $class->_validation_failures;
			ConvoTreeEngine::Exception::Input->throw(
				error => "Validation for Element JSON did not pass:\n$failures",
				code  => 400,
			);
		}

		return JSON::encode_json($json);
	}

	my @failures;
	my $nested = 0;
	sub _validate_value {
		my $invocant   = shift;
		my $value      = shift;
		my @additional = @_;
		my $validation = pop @additional;

		my $class = ref $invocant || $invocant;

		if ($nested == 0) {
			@failures = ();
		}
		$nested++;

		$validation = [$validation] unless ref $validation;
		unshift @additional, $value;

		my $isValid;
		foreach my $v (@$validation) {
			if ($v =~ m/^arrayOf\((.*)\)\z/) {
				my $patterns = $1;
				my @patterns = split m/\s*,\s*/, $patterns;
				foreach my $pattern (@patterns) {
					ConvoTreeEngine::Exception::Input->throw(
						error => "Validation '$pattern' does not exist",
					) unless $validations{$pattern};
				}
				$isValid = $arrayOf->($class, $value, @patterns);
			}
			else {
				ConvoTreeEngine::Exception::Input->throw(
					error => "Validation '$v' does not exist",
				) unless $validations{$v};

				$isValid = $validations{$v}->($class, @additional);
			}
			if ($isValid) {
				$nested--;
				return $isValid;
			}
		}

		my $displayValue = ref $value ? JSON::encode_json($value) : $value;
		push @failures, "* Value(s) '" . $displayValue . "' did not meet validation(s) '" . join("', '", @$validation) . "'";

		$nested--;
		return $isValid;
	}

	sub _validation_failures {
		my $invocant = shift;

		return join "\n", @failures;
	}
}

#===================#
#== Other Methods ==#
#===================#

sub listReferencedElements {
	my $self          = shift;
	my $verify_exists = shift;

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
	elsif ($type eq 'assess') {
		if (@{$jsonRef->{cond}} > 1) {
			if (ref $jsonRef->{cond}[1]) {
				push @elements, @{$jsonRef->{cond}[1]};
			}
			else {
				push @elements, $jsonRef->{cond}[1];
			}
		}
	}
	elsif ($type eq 'negate') {
		if (ref $jsonRef->{assess_id}) {
			push @elements, @{$jsonRef->{assess_id}};
		}
		else {
			push @elements, $jsonRef->{assess_id};
		}
	}
	elsif ($type eq 'choice') {
		foreach my $choice (@{$jsonRef->{choices}}) {
			if (@$choice > 2) {
				if (ref $choice->[2]) {
					push @elements, @{$choice->[2]};
				}
				else {
					push @elements, $choice->[2];
				}
			}
		}
	}
	elsif ($type eq 'data') {
		if (ref $jsonRef->{get}) {
			push @elements, @{$jsonRef->{get}};
		}
		else {
			push @elements, $jsonRef->{get};
		}
	}
	elsif ($type eq 'series') {
		if (ref $jsonRef->{series}) {
			push @elements, @{$jsonRef->{series}};
		}
		else {
			push @elements, $jsonRef->{series};
		}
	}

	my %elements = map {$_ => 1} @elements;
	@elements = keys %elements;

	if ($verify_exists) {
		if ($type eq 'negate') {
			foreach my $id (@elements) {
				ConvoTreeEngine::Object::Element->findOrDie({id => $id, type => 'assess'});
			}
		}
		else {
			foreach my $id (@elements) {
				ConvoTreeEngine::Object::Element->findOrDie({id => $id});
			}
		}
	}

	return @elements;
}

sub doNestedElements {
	my $self = shift;

	if (my @elements = $self->listReferencedElements(1)) {
		my $type = $self->type;
		if ($type eq 'if' || $type eq 'assess' || $type eq 'choice' || $type eq 'series') {
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

	require ConvoTreeEngine::Object::Element::Nested;
	my $e_table  = $self->_table;
	my $ne_table = ConvoTreeEngine::Object::Element::Nested->_table;
	my $rows = ConvoTreeEngine::Mysql->fetchRows(qq/
		SELECT e.id, e.type, e.name, e.category, e.json FROM $ne_table ne
		JOIN $e_table e ON ne.element_id = e.id
		WHERE ne.nested_element_id = ?;
	/, [$self->id]);

	return unless @$rows;

	foreach my $row (@$rows) {
		my $type    = $row->{type};
		my $element = $self->promote($row);
		my $jsonRef = $element->jsonRef;

		if ($type eq 'if') {
			foreach my $cond (@{$jsonRef->{cond}}) {
				if (@$cond > 1) {
					$cond->[1] = $element->_sanitize_nesting_arrays($cond->[1], $self->id);
				}
			}
		}
		elsif ($type eq 'assess') {
			if (@{$jsonRef->{cond}} > 1) {
				$jsonRef->{cond}[1] = $element->_sanitize_nesting_arrays($jsonRef->{cond}[1], $self->id);
			}
		}
		elsif ($type eq 'choice') {
			foreach my $choice (@{$jsonRef->{choices}}) {
				if (@$choice > 2) {
					$choice->[2] = $element->_sanitize_nesting_arrays($choice->[2], $self->id);
				}
			}
		}
		elsif ($type eq 'series') {
			$jsonRef->{series} = $element->_sanitize_nesting_arrays($jsonRef->{series}, $self->id);
		}

		$element->update({json => $jsonRef, skip_nested => 1});
	}

	ConvoTreeEngine::Mysql->doQuery(qq/
		DELETE FROM $ne_table
		WHERE nested_element_id = ?;
	/, [$self->id]);

	return;
}

sub _sanitize_nesting_arrays {
	my $self         = shift;
	my $nestingBlock = shift;
	my $to_remove    = shift;

	my @elements;
	if (ref $nestingBlock) {
		foreach my $id (@$nestingBlock) {
			push @elements, $id unless $id == $to_remove;
		}
	}
	else {
		unless ($nestingBlock == $to_remove) {
			push @elements, $nestingBlock;
		}
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

	my $hash = $self->jsonRef;
	$hash->{type}     = $self->type;
	$hash->{id}       = $self->id;
	$hash->{name}     = $self->name;
	$hash->{category} = $self->category;

	return $hash;
}

1;