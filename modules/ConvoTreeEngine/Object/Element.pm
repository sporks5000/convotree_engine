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
	}
	my $boolean = sub {
		### Returns true if the value is strictly boolean
		my $value = shift;
		return 1 if !defined $value;
		return 1 if $value =~ /^[01]\z/;
		return 1 if ref($value) && $value->isa('JSON::Boolean');
		return 0;
	};
	my $hash = sub {
		my $value = shift;
		return 0 unless (ref $value || '' ) eq 'HASH';
		return 1;
	};
	my $array = sub {
		my $value = shift;
		return 0 unless (ref $value || '' ) eq 'ARRAY';
		return 1;
	};
	my $variableName = sub {
		### Returns true if the value matches what we expect from a javascript variable name
		my $value = shift;
		return 0 unless defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^[a-zA-Z0-9_.]+\z/;
		return 1;
	};
	my $words = sub {
		### Returns true if the value is a string of words separated by either single spaces or single hyphens
		my $value = shift;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(?:[a-zA-Z0-9_]+[ -]?)+\b\z/;
		return 1;
	};
	my $string = sub {
		### returns true if the value is a text string
		my $value = shift;
		return 0 if ref $value;
		return 1 if defined $value && length $value;
		return 0;
	};
	my $positiveInt = sub {
		### Returns true if the value looks like a positive integer
		my $value = shift;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^[1-9][0-9]*|0\z/;
		return 1;
	};
	my $number = sub {
		### Returns true if the value looks like a logical number, either positive or negative, with or without decimal places
		my $value = shift;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(-?[1-9][0-9]*|0)(\.[0-9]+)?\z/;
		return 1;
	},
	my $pathIdent = sub {
		### Returns true if the value looks like a an identifier for a path or a series
		my $value = shift;
		return 0 if !defined $value;
		return 0 if ref $value;
		return 0 if $value !~ m/^(path|series)[0-9]+\z/i;
		return 1;
	};
	my $itemBlock; $itemBlock = sub {
		my $value = shift;
		return 0 unless $array->($value);
		### The first element will either be undefined or a string of words
		return 0 if defined $value->[0] && $words->($value->[0]);
		### The second element must be undefined, or a string, or another item block
		return 0 if defined $value->[1] && !$string->($value->[1]) && !$itemBlock->($value->[1]);
		### If the second element is undefined, the third element must be a single word (representing a variable name)
		### Otherwise, there must be no third element
		return 0 if defined $value->[1] && @$value > 2;
		return 0 if !defined $value->[1] && !defined $value->[2];
		return 0 if defined $value->[2] && !$variableName->($value->[2]);
		return 0 if @$value > 3;
		return 1;
	};
	my $item = sub {
		### The value must be an array of arrays
		my $value = shift;
		return 0 unless $array->($value);
		foreach my $deep (@$value) {
			return 0 unless $itemBlock->($deep);
		}
		return 1;
	};
	my $elements; $elements = sub {
		### Either a hashref matching what's expected from an ConvoTreeEngine::Object::Element object (not including the ID)
		### ...or positive integer representing the ID of an ConvoTreeEngine::Object::Element object
		### ...or the word 'SERIES' followed by a positive integer represending an ConvoTreeEngine::Object::Series object
		### ...or an arrayref made up of any/all of the above
		my $value = shift;
		my $type  = shift;
		return 0 unless defined $value;
		my $ref = ref $value || '';
		if ($ref eq 'ARRAY') {
			foreach my $element (@$value) {
				return 0 unless $elements->($element);
			}
		}
		elsif ($ref eq 'HASH') {
			$type ||= $value->{type};
			return 0 unless $type;
			return 0 unless $typeValidation{$type};
			foreach my $key (keys %$value) {
				next if $key eq 'type';
				return 0 unless $typeValidation{$type}{$key};
			}
			foreach my $key (keys %{$typeValidation{$type}}) {
				next unless $typeValidation{$type}{$key}[0] && exists $value->{$key};
				return 0 if !exists $value->{$key};
				### Make sure it passes validation for that element type
				my $test = $typeValidation{$type}{$key}[1];
				return 0 unless $test->($value->{$key});
			}
		}
		else {
			return 0 if $value !~ m/^(SERIES)?[0-9]+\z/;
		}
		return 1;
	};
	my $conditionString = sub {
		### A string of text, potentially of multiple parts separated with and/or operators ('&' or '\')
		my $value = shift;
		return 1 if !defined $value;
		return 0 if ref $value;
		return 0 if !length $value;
		my @parts = split m/\s*(&|\|)\s*/, $value;
		foreach my $part (@parts) {
			### Each part contains a variable name, an operator, and a condition
			my ($varName, $cond, @other) = split m/\s*(=|!=|>|<|>=|<=)\s*/, $part;
			return 0 if @other;
			my $operator = do {
				$part =~ m/(=|!=|>|<|>=|<=)/;
				$1;
			};
			return 0 unless $variableName->($varName);
			if ($operator =~ m/[<>]/) {
				### If the operator is specific to numbers, make sure that the condition is a number
				return 0 unless $number->($cond);
			}
			else {
				### Otherwise the condition can be a single word
				return 0 if $cond !~ m/^[a-zA-Z0-9_]+\z/;
			}
		}
		return 1;
	};
	my $singleCondition = sub {
		### the value will be an array
		my $value = shift;
		return 0 unless $array->($value);
		### The first element will either be undefined or a condition string
		return 0 if defined $value->[0] && !$conditionString->($value->[0]);
		return 0 if @$value > 2;
		return 1 unless @$value == 2;
		### If the second element is present, it should be a path identifier
		return 0 unless $pathIdent->($value->[1]);
		return 1;
	};
	my $ifConditions = sub {
		### The value must be an array of arrays
		my $value = shift;
		return 0 unless $array->($value);
		foreach my $deep (@$value) {
			return 0 unless $singleCondition->($deep);
		}
		return 1;
	};
	my $variableUpdates = sub {
		### Returns true if given a hash of variable names to strings (or undefineds)
		my $value = shift;
		return 0 unless $hash->($value);
		foreach my $key (keys %$value) {
			return 0 unless $variableName->($key);
			return 0 unless !defined $value->{$key} || $string->($value->{$key});
		}
		return 1;
	};
	my $choices = sub {
		### The value must be an array of arrays
		my $value = shift;
		return 0 unless $array->($value);
		foreach my $deep (@$value) {
			return 0 unless defined $deep;
			return 0 unless $array->($deep);
			### The first element will be a condition string
			return 0 unless $conditionString->($deep->[0]);
			### The second element will be what we display for the choice
			return 0 unless $string->($deep->[1]);
			next if @$deep == 2;
			return 0 if @$deep > 3;
			### If there is a third element, it should be a path identifier
			return 0 unless $pathIdent->($deep->[2]);
		}
		return 1;
	};

	%typeValidation = (
		item     => {
			text  => [1, $item],
			arbit => [0, $ignore],
		},
		note     => {
			note  => [1, $string],
			arbit => [0, $ignore],
		},
		raw      => {
			html   => [1, $string],
			arbit  => [0, $ignore],
		},
		enter    => {
			start => [1, $string],
			end   => [1, $string],
			name  => [1, $words],
			arbit => [0, $ignore],
		},
		exit     => {
			name  => [1, sub {
				my $value = shift;
				return 1 if !defined $value;
				return 1 if $words->($value);
				return 0;
			}],
			all   => [0, $boolean],
			arbit => [0, $ignore],
		},
		if       => {
			cond  => [1, $ifConditions],
			arbit => [0, $ignore],
		},
		assess   => {
			cond  => [1, $singleCondition],
			arbit => [0, $ignore],
		},
		varaible => {
			update => [1, $variableUpdates],
			arbit  => [0, $ignore],
		},
		choice   => {
			choices => [1, $choices],
			arbit  => [0, $ignore],
		},
		display  => {
			disp  => [1, $hash],
			arbit => [0, $ignore],
		},
		do       => {
			function => [1, sub {
				my $value = shift;
				return 0 if $value !~ m/^[a-zA-Z0-9_]+\z/;
				return 1;
			}],
			args     => [0, $array],
			arbit    => [0, $ignore],
		},
		data     => {
			get   => [1, $elements],
			arbit => [0, $ignore],
		},
	);

	sub _validate_json {
		my $invocant = shift;
		my $json     = shift;
		my $type     = shift;

		unless (ref $json) {
			$json = JSON::decode_json($json);
		}

		my $success = $elements->($json, $type);
		ConvoTreeEngine::Exception::Input->throw(
			error => 'Validation for Element JSON did not pass',
			code  => 400,
		) unless $success;

		return JSON::encode_json($json);
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