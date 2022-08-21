package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

sub _table {
	return 'element';
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

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my ($attrString, $bits) = $invocant->_parse_query_attrs($attrs);

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
	push @input, @$bits;
	my $table = $invocant->_table;
	my $query = qq/
		SELECT id, type, name, category, json FROM $table
		$whereString
		$attrString
	/;
	my $rows = ConvoTreeEngine::Mysql->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

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

#================#
#== Validation ==#
#================#

{
	my %typeValidation;

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
	my $itemText = sub {
		### The value must be an array of arrays
		my $value = shift;
		return 0 unless $array->($value);
		foreach my $deep (@$value) {
			return 0 unless $array->($deep);
			foreach my $deeper (@$deep) {
				return 0 if ref $deeper;
			}
			### The first element will either be undefined or a string of words
			return 0 if defined $deep->[0] && $words->($deep->[0]);
			### The second element must be undefined or a string
			return 0 if defined $deep->[1] && !$string->($deep->[1]);
			### If the second element is undefined, the third element must be a single word (representing a variable name)
			### Otherwise, there must be no third element
			return 0 if defined $deep->[1] && @$deep > 2;
			return 0 if !defined $deep->[1] && !defined $deep->[2];
			return 0 if defined $deep->[2] && !$variableName->($deep->[2]);
			return 0 if @$deep > 3;
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
			return 0 if $value =~ m/^(SERIES)?[0-9]+\z/;
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
		### If the second element is present, it will match the $elements test
		return 0 unless $elements->($value->[1]);
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
			### If there is a third element, it will match the $elements test
			return 0 unless $elements->($deep->[2]);
		}
		return 1;
	};

	%typeValidation = (
		item     => {
			text   => [1, $itemText],
			delay  => [0, $positiveInt],
			prompt => [0, $boolean],
		},
		note     => {
			note => [1, $string],
		},
		raw      => {
			html   => [1, $string],
			delay  => [0, $positiveInt],
			prompt => [0, $boolean],
		},
		enter    => {
			start => [1, $string],
			end   => [1, $string],
			name  => [1, $words],
		},
		exit     => {
			name => [1, sub {
				my $value = shift;
				return 1 if !defined $value;
				return 1 if $words->($value);
				return 0;
			}],
			all  => [0, $boolean],
		},
		if       => {
			cond => [1, $ifConditions],
		},
		assess   => {
			cond => [1, $singleCondition],
		},
		varaible => {
			update => [1, $variableUpdates],
		},
		choice   => {
			choices => [1, $choices],
		},
		display  => {
			disp  => [1, $hash],
			delay => [0, $positiveInt],
		},
		do       => {
			function => [1, sub {
				my $value = shift;
				return 0 if $value !~ m/^[a-zA-Z0-9_]+\z/;
				return 1;
			}],
			args     => [0, $array],
		},
		data     => {
			get => [1, $elements],
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
		) unless $success;

		return JSON::encode_json($json);
	}
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