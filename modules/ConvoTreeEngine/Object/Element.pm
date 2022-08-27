package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

use ConvoTreeEngine::Object::ElementPath;

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

		$self->doElementPaths;
	});

	return $self;
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my $skip_paths = delete $args->{skip_paths};
	$args->{json} = $self->_validate_json($args->{json}, $self->type) if exists $args->{json};

	$self->atomic(sub {
		$self = $self->SUPER::update($args);

		$self->doElementPaths unless $skip_paths;
	});

	return $self;
}

### Uses "search" and "delete" from the base class

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
		### returns true if the value is a text string
		my ($class, $value) = @_;
		return 0 if ref $value;
		return 1 if defined $value && length $value;
		return 0;
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
	my $pathIdent = sub {
		### Returns true if the value looks like a an identifier for a path or a series
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(path|series)[0-9]+\z/i;
		return 1;
	};
	my $elementString = sub {
		### Returns true if the value looks like a an identifier for a series or element
		my ($class, $value) = @_;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(series)?[0-9]+\z/i;
		return 1;
	};
	my $itemBlock; $itemBlock = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will either be undefined or a string of words
		return 0 if defined $value->[0] && $class->_validate_value($value->[0], 'words');
		### The second element must be undefined, or a string, or another item block
		return 0 if defined $value->[1] && !$class->_validate_value($value->[1], 'string') && !$class->_validate_value($value->[0], 'itemBlock');
		### If the second element is undefined, the third element must be a single word (representing a variable name)
		### Otherwise, there must be no third element
		return 0 if defined $value->[1] && @$value > 2;
		return 0 if !defined $value->[1] && !defined $value->[2];
		return 0 if defined $value->[2] && !$class->_validate_value($value->[2], 'variableName');
		return 0 if @$value > 3;
		return 1;
	};
	my $item = sub {
		### The value must be an array of arrays
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		foreach my $deep (@$value) {
			return 0 unless $class->_validate_value($deep, 'itemBlock');
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
			return 0 unless $class->_validate_value($value->{$key}, $typeValidation{$type}{$key}[1]);
		}
		return 1;
	};
	my $elementStrings = sub {
		### An array of element strings, or a single element string
		my ($class, $value) = @_;
		return 0 unless defined $value;
		my $ref = ref $value || '';
		if ($ref eq 'ARRAY') {
			foreach my $element (@$value) {
				return 0 unless $class->_validate_value($element, 'elementString');
			}
		}
		else {
			return 0 unless $class->_validate_value($value, 'elementString');
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
		### If the second element is present, it should be a path identifier
		return 0 unless $class->_validate_value($value->[1], 'pathIdent');
		return 1;
	};
	my $ifConditions = sub {
		### The value must be an array of arrays
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		foreach my $deep (@$value) {
			return 0 unless $class->_validate_value($deep, 'singleCondition');
		}
		return 1;
	};
	my $variableUpdates = sub {
		### Returns true if given a hash of variable names to strings (or undefineds)
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'hash');
		foreach my $key (keys %$value) {
			return 0 unless $class->_validate_value($key, 'variableName');
			return 0 unless !defined $value->{$key};
			return 0 unless $class->_validate_value($value->{$key}, 'string');
			return 0 if $value->{$key} =~ m/^[+*\/-]=/ && !$class->_validate_value(substr($value->{$key}, 2), 'number');
		}
		return 1;
	};
	my $choices = sub {
		### The value must be an array of arrays
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		foreach my $deep (@$value) {
			return 0 unless defined $deep;
			return 0 unless $class->_validate_value($deep, 'array');
			### The first element will be a condition string
			return 0 unless $class->_validate_value($deep->[0], 'conditionString');
			### The second element will be what we display for the choice
			return 0 unless $class->_validate_value($deep->[1], 'string');
			next if @$deep == 2;
			return 0 if @$deep > 3;
			### If there is a third element, it should be a path identifier
			return 0 unless $class->_validate_value($deep->[2], 'pathIdent');
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
		pathIdent       => $pathIdent,
		itemBlock       => $itemBlock,
		item            => $item,
		singleElement   => $singleElement,
		elementStrings  => $elementStrings,
		conditionString => $conditionString,
		singleCondition => $singleCondition,
		ifConditions    => $ifConditions,
		variableUpdates => $variableUpdates,
		choices         => $choices,
	);

	%typeValidation = (
		item     => {
			text   => [1, 'item'],
			delay  => [0, 'positiveInt'],
			prompt => [0, 'boolean'],
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
			cond  => [1, 'ifConditions'],
			arbit => [0, 'ignore'],
		},
		assess   => {
			cond  => [1, 'singleCondition'],
			arbit => [0, 'ignore'],
		},
		negate   => {
			assess_id => [1, 'positiveInt'],
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
			choices => [1, 'choices'],
			arbit   => [0, 'ignore'],
		},
		display  => {
			disp  => [1, 'hash'],
			delay => [0, 'positiveInt'],
			arbit => [0, 'ignore'],
		},
		do       => {
			function => [1, 'word'],
			args     => [0, 'array'],
			delay    => [0, 'positiveInt'],
			arbit    => [0, 'ignore'],

		},
		data     => {
			get   => [1, 'elementStrings'],
			arbit => [0, 'ignore'],
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
	my $top = 1;
	sub _validate_value {
		my $invocant   = shift;
		my $value      = shift;
		my @additional = @_;
		my $validation = pop @additional;

		my $class = ref $invocant || $invocant;

		my $prev_top = $top;
		if ($top == 1) {
			@failures = ();
		}
		$top = 0;

		$validation = [$validation] unless ref $validation;
		unshift @additional, $value;

		my $isValid;
		foreach my $v (@$validation) {
			ConvoTreeEngine::Exception::Input->throw(
				error => "Validation '$v' does not exist",
			) unless $validations{$v};

			$isValid = $validations{$v}->($class, @additional);
			return $isValid if $isValid;
		}

		my $displayValue = ref $value ? JSON::encode_json($value) : $value;
		push @failures, "* Value(s) '" . $displayValue . "' did not meet validation(s) '" . join("', '", @$validation) . "'";

		$top = $prev_top;
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

sub elementPaths {
	my $self = shift;

	my %paths = map {$_->id => $_} ConvoTreeEngine::Object::ElementPath->search({element_id => $self->id});
	return \%paths;
}

sub doElementPaths {
	my $self = shift;

	my $jsonRef = $self->jsonRef;
	my $paths = $self->elementPaths;

	my $doUpdate = 0;
	my $type = $self->type;
	if ($type eq 'if') {
		foreach my $condition (@{$jsonRef->{cond}}) {
			if (@$condition > 1) {
				if (my $update = $self->_confirm_element_path($condition->[1], $paths)) {
					$condition->[1] = $update;
					$doUpdate = 1;
				}
			}
		}
	}
	elsif ($type eq 'assess') {
		my $condition = $jsonRef->{cond};
		if (@$condition > 1) {
			if (my $update = $self->_confirm_element_path($condition->[1], $paths)) {
				$condition->[1] = $update;
				$doUpdate = 1;
			}
		}
	}
	elsif ($type eq 'choice') {
		foreach my $choice (@{$jsonRef->{choices}}) {
			if (@$choice > 2) {
				if (my $update = $self->_confirm_element_path($choice->[2], $paths)) {
					$choice->[2] = $update;
					$doUpdate = 1;
				}
			}
		}
	}

	if ($doUpdate) {
		$self->update({json => $jsonRef, skip_paths => 1});
	}
	if (%$paths) {
		my $toDelete = join(', ', keys %$paths);
		my $table = ConvoTreeEngine::Object::ElementPath->_table;
		ConvoTreeEngine::Mysql->doQuery(
			qq/DELETE FROM $table WHERE id IN ($toDelete);/,
		);
	}

	return;
}

sub _confirm_element_path {
	my $self    = shift;
	my $pathVar = shift;
	my $paths   = shift;

	my $updated;
	my $path_id;
	if ($pathVar =~ m/^path([0-9]+)\z/i) {
		$path_id = $1;
		my $path = ConvoTreeEngine::Object::ElementPath->findOrDie({id => $path_id});
		if ($path->element_id != $self->id) {
			my %pathArgs = (element_id => $self->id, series_id => $path->series_id);
			$path = ConvoTreeEngine::Object::ElementPath->find(\%pathArgs) || ConvoTreeEngine::Object::ElementPath->create(\%pathArgs);
			$path_id = $path->id;
		}
		if ($pathVar ne "PATH$path_id") {
			$updated = "PATH$path_id";
		}
	}
	elsif ($pathVar =~ m/^series([0-9]+)\z/i) {
		my $series_id = $1;
		my %pathArgs = (element_id => $self->id, series_id => $series_id);
		my $path = ConvoTreeEngine::Object::ElementPath->find(\%pathArgs) || ConvoTreeEngine::Object::ElementPath->create(\%pathArgs);
		$path_id = $path->id;
		$updated = "PATH$path_id";
	}

	delete $paths->{$path_id};

	return $updated;
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