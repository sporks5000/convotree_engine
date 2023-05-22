package ConvoTreeEngine::Validation;

use strict;
use warnings;

our $STRICT_ITEM_TYPE_VALIDATION = 1;

my %elementTypeValidation;

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
	return 1 if $class->validateRegex($value, '^[01]\z');
	return 0;
};
my $hash = sub {
	my ($class, $value) = @_;
	return 0 unless (ref $value || '') eq 'HASH';
	return 1;
};
my $array = sub {
	my ($class, $value) = @_;
	return 0 unless (ref $value || '') eq 'ARRAY';
	return 1;
};
my $namecat = sub {
	### Returns true if the value looks like a namecat
	### A namecat must validate as 'dashWords' followed by a colon, followed by 'dashWords'. Either instance of 'dashWords' can instead be an empty string, but not both
	### NOTE that while a namecat can be undefined, a undefined value DOES NOT validate as a namecat
	my ($class, $value) = @_;
	return 0 if $class->validateRegex($value, ':', 1);
	my ($cat, $name, @other) = split m/:/, $value;
	return 0 if @other;
	return 0 if $cat  && !$class->validateValue($cat,  'dashWords');
	return 0 if $name && !$class->validateValue($name, 'dashWords');
	return 1;
};
my $elementList = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, ['positiveInt', 'namecat', 'arrayOf(positiveInt,namecat)']);
	return 1;
};
my $itemTextNested = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'array');
	### The first element will either be undefined or a string of dashWords
	return 0 if defined $value->[0] && !$class->validateValue($value->[0], 'dashWords');
	### The second element must be undefined, or a string, or another item block
	if (defined $value->[1]) {
		return 0 unless $class->validateValue($value->[1], ['string', 'arrayOf(1,itemTextNested)']);
		### If it is defined, there cannot be a third element
		return 0 unless @$value == 2;
	}
	else {
		### If the second element is undefined, the third must match the validation for a variable name
		return 0 unless @$value == 3;
		return 0 unless $class->validateValue($value->[2], 'variableName');
	}
	return 1;
};
my $itemTextHash = sub {
	my ($class, $value) = @_;
	return $class->validateValue($value, 'hashOf', {
		speaker => [0, 'dashWords'],
		text    => [1, ['string', 'arrayOf(1,itemTextNested)']],
		classes => [0, 'dashWords'],
		hover   => [0, 'string'],
		frame   => [0, 'dashWords']
	});
},
my $singleElement = sub {
	### Return true if the value has the structure of a single element
	my ($class, $value, $type) = @_;
	return 0 unless defined $value;
	return 0 unless (ref $value || '') eq 'HASH';
	$type ||= $value->{type};
	return 0 unless $type;
	return 0 unless $elementTypeValidation{$type};
	### Make sure that we're ignoring type, if present
	local $elementTypeValidation{$type}{type} ||= [0, 'ignore'];
	return $class->validateValue($value, 'hashOf', $elementTypeValidation{$type});
};
my $conditionString = sub {
	### A string of text
	my ($class, $value) = @_;
	return 1 if !defined $value;
	return 0 if ref $value;
	return 0 if !length $value;
	### Set aside quoted strings that might contain special characters
	my @quoted;
	my $valueMod = '';
	while ($value =~ m/^(.*)('[^']*'|"[^"]*")(.*)$/) {
		$valueMod .= "$1'''";
		$value = $3 // '';
		push @quoted, $2;
	}
	### If there's an extra quote at the end, the string we were passed was malformed
	return 0 if $value =~ m/['"]/;
	$valueMod .= $value;
	my @parts = split m/\s*[&|]\s*/, $valueMod;
	foreach my $part (@parts) {
		### Put the quoted bits back
		my $quoted_count = $part =~ m/'''/g;
		if ($quoted_count) {
			my @pieces = split m/'''/, $part;
			if (@pieces == $quoted_count) {
				push @pieces, '';
			}
			if ($part =~ m/^'''/) {
				unshift @pieces, '';
			}
			$part = shift @pieces;
			while (@pieces) {
				$part .= shift(@quoted) . shift(@pieces);
			}
		}
		if ($part =~ m/^!?seen:(.*)$/i) {
			### A part can also be the string "seen:" followed by an identifier for an element (indicating that that element has already been seen by the user)
			### If it's preceeded by an exclamation point, that means that it hasn't been seen
			my $seen = $1;
			return 0 unless $class->validateValue($seen, ['positiveInt', 'namecat']);
			next;
		}
		elsif ($part =~ m/^!?function:(.*)$/i) {
			### A part can indicate the name of a javascript function that will return a true or false value
			my $func = $1;
			return 0 unless $class->validateValue($func, 'word');
			next;
		}
		elsif ($part =~ m/^!?first\z/i) {
			### A part can be the word "first" indicating that no options previous to this one have returned true
			next;
		}
		### Each part contains a variable name, an operator, and a condition
		my $operator = do {
			$part =~ m/([!><=]=|[=><]|!==)/;
			$1;
		};
		return 0 unless $operator;
		my ($varName, $cond, @other) = split m/\s*$operator\s*/, $part;
		### If it starts with an exclamation point, strip that out
		$varName = substr($varName, 1) if substr($varName, 0, 1) eq '!';
		return 0 if @other;
		return 0 unless $class->validateValue($varName, 'variableName');
		if ($operator =~ m/[<>]|==/) {
			### If the operator is specific to numbers, make sure that the condition is a number
			return 0 unless $class->validateValue($cond, 'number');
		}
		else {
			if ($cond =~m/^(['"])(.*)\1\s*\z/) {
				### If it's a quoted string, just take what's in the quotes
				$cond = $2;
				return 0 unless $class->validateValue($cond, 'string');
			}
			else {
				### Otherwise make sure that it has no spaces or special characters
				return 0 if $cond =~ m/\s/;
				return 0 unless $class->validateValue($cond, 'word');
			}
		}
	}
	return 1;
};
my $condition = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, ['undefined', 'conditionString', 'conditionBlock', 'arrayOf(condition)']);
	return 1;
};
my $conditionBlock = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'hashOf', {
		not => [0, 'condition'],
		and => [0, 'condition'],
		or  => [0, 'condition'],
		xor => [0, 'condition'],
	});
	### Make sure it contains at least one of the above keys
	return 1 unless scalar keys %$value == 0;
};
my $ifConditionBlock = sub {
	### the value will be an array
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'array');
	### The first element will either be undefined or a condition string
	return 0 unless $class->validateValue($value->[0], 'condition');
	return 0 if @$value > 2;
	return 1 unless @$value == 2;
	### If the second element is present, it should be an element ID or an array of element IDs
	return 0 unless $class->validateValue($value->[1], 'elementList');
	return 1;
};
my $variableUpdates = sub {
	### Returns true if given a hash of variable names to strings (or undefineds)
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'hash');
	foreach my $key (keys %$value) {
		return 0 unless $class->validateValue($key, 'variableName');
		### The strings for updating numerical values could be parsed, but if they failed, we'd
		### just check them against "string" anyway, and they'd pass that, so there's no point.
		return 0 unless $class->validateValue($value->{$key}, ['string', 'undefined']);
		return 0 if $value->{$key} =~ m/^[+\*\/-]=/ && !$class->validateValue(substr($value->{$key}, 2), 'number');
	}
	return 1;
};
my $choice = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'hashOf', {
		cond          => [0, 'condition'],
		element       => [1, ['positiveInt', 'namecat']],
		then          => [0, 'elementList'],
		disp_inactive => [0, 'boolean'],
		classes       => [0, 'dashWords'],
		arbit         => [0, 'ignore'],
	});
	### The element MUST be of type "item"
	return 1 unless $STRICT_ITEM_TYPE_VALIDATION;
	my $element = ConvoTreeEngine::Object::Element->find($value->{element});
	return 0 unless $element;
	return 0 unless $element->type eq 'item';
	return 1;
};
my $randomPath = sub {
	my ($class, $value) = @_;
	return 0 unless $class->validateValue($value, 'array');
	return 0 unless @$value == 2;
	return 0 unless $class->validateValue($value->[0], 'positiveInt');
	return 0 unless $class->validateValue($value->[1], 'elementList');
	return 1;
};
my $arrayOf = sub {
	my ($class, $value, @patterns) = @_;
	return 0 unless $class->validateValue($value, 'array');
	if ($patterns[0] eq '1') {
		shift @patterns;
		return 0 unless @$value;
	}
	return 0 unless @patterns;
	foreach my $deep (@$value) {
		return 0 unless $class->validateValue($deep, \@patterns);
	}
	return 1;
};
my $hashOf = sub {
	my ($class, $value, @patterns) = @_;
	return 0 unless $class->validateValue($value, 'hash');
	return 0 unless @patterns;
	my %flags;
	if (!ref $patterns[-1]) {
		my $flags = shift @patterns;
		return 0 unless @patterns;
		%flags = map {$_ => 1} split m/\s*,\s*/, $flags;
	}
	my $match = 0;
	PATTERN:
	foreach my $pattern (@patterns) {
		next PATTERN unless $class->validateValue($pattern, 'hash');
		unless ($flags{keep_extra}) {
			### Fail out if there are extra keys
			foreach my $key (keys %$value) {
				next PATTERN unless $pattern->{$key};
			}
		}
		KEY:
		foreach my $key (keys %$pattern) {
			next PATTERN unless $class->validateValue($pattern->{$key}, 'array');
			### If it's not present and not required, that's fine
			next KEY unless $pattern->{$key}[0] && exists $value->{$key};
			next PATTERN unless exists $value->{$key};
			### Make sure it passes validation for that element type
			my $validation = $pattern->{$key}[1];
			my @args = ($value->{$key});
			if (scalar @{$pattern->{$key}} > 2) {
				push @args, @{$pattern->{$key}}[2..$#{$pattern->{$key}}];
			}
			next PATTERN unless $class->validateValue(@args, $validation);
		}
		$match = 1;
		last PATTERN;
	}
	return $match
};

my %validations = (
	ignore           => $ignore,
	undefined        => $undefined,
	boolean          => $boolean,
	hash             => $hash,
	array            => $array,
	variableName     => '^[a-zA-Z0-9_.]+\z', # A pattern we're specifcally using for variable names
	words            => '^(?:[a-zA-Z0-9_]+ ?)+\b\z', # A string of words separated by either single spaces
	dashWords        => '^(?:[a-zA-Z0-9_]+[ -]?)+\b\z', # A string of words separated by either single spaces or single hyphens
	word             => '^[a-zA-Z0-9_]+\z', # A single word containg letters numbers and/or underscores
	string           => '^[^\x00-\x09\x0B\x0C\x0E-\x1F\x7F]*$', # No control characters other than "Line Feed" and "Carriage Return"
	positiveInt      => '^[1-9][0-9]*\z', # Looks like a positive integer
	number           => '^(-?[1-9][0-9]*|0)(\.[0-9]+)?\z', # Looks like a number
	namecat          => $namecat,
	elementList      => $elementList,
	itemTextNested   => $itemTextNested,
	itemTextHash     => $itemTextHash,
	singleElement    => $singleElement,
	condition        => $condition,
	conditionString  => $conditionString,
	conditionBlock   => $conditionBlock,
	ifConditionBlock => $ifConditionBlock,
	variableUpdates  => $variableUpdates,
	choice           => $choice,
	randomPath       => $randomPath,
	arrayOf          => $arrayOf,
	hashOf           => $hashOf,
);

=head2 elementTypeValidation

A hashref of element types. For each type, there will be a hashref of key/value pairs in that type. The
value will be an array with two elements - Boolean representing if it's required, and eith a string or
an array of strings indicating validators for what can be present.

=cut

%elementTypeValidation = (
	item     => {
		text     => [1, ['string', 'arrayOf(1,itemTextNested)', 'itemTextHash']],
		textx    => [0, ['string', 'arrayOf(1,itemTextNested)', 'itemTextHash']],
		function => [0, 'word'],
		delay    => [0, 'positiveInt'],
		prompt   => [0, ['boolean', 'string', 'arrayOf(1,itemTextNested)', 'itemTextHash']],
		arbit    => [0, 'ignore'],
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
		cond  => [1, 'arrayOf(1,ifConditionBlock)'],
		arbit => [0, 'ignore'],
	},
	stop     => {
		arbit     => [0, 'ignore'],
	},
	variable => {
		update => [1, 'variableUpdates'],
		arbit  => [0, 'ignore'],
	},
	choice   => {
		choices => [1, 'arrayOf(1,choice)'],
		delay   => [0, 'positiveInt'],
		classes => [0, 'dashWords'],
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
	elements => {
		get   => [0, 'elementList'],
		queue => [0, 'elementList'],
		arbit => [0, 'ignore'],
	},
	random   => {
		paths    => [1, 'arrayOf(1,randomPath)'],
		function => [1, 'word'],
		arbit    => [0, 'ignore'],
	},
);

=head2 validateElementJson

Given either a JSON blob or a hashref, and an element type, validate that the data given matches that
type.

=cut

sub validateElementJson {
	my $class = shift;
	my $json  = shift;
	my $type  = shift;

	unless (ref $json) {
		$json = JSON::decode_json($json);
	}

	my $isValid = $class->validateValue($json, 'singleElement', $type);
	unless ($isValid) {
		my $failures = $class->_validation_failures;
		ConvoTreeEngine::Exception::Input->throw(
			error => "Validation for Element JSON did not pass:\n$failures",
			code  => 400,
		);
	}

	return JSON::encode_json($json);
}

=head2 validateRegex

Verify that a value is a scalar and matches (or does not match) a regular expression.

Note: Under the vast majority of circumstances, this should be called with an "if" and not an
"unless", as regardless of whether we're negating, this will return fales if the value passed
is undefined, or if it is not a string.

=head3 Arguments

* $value  - The value we're validating
* $regex  - The regular expression we're validating against
* $negate - Boolean; true if we want to NOT match the regular expression

=cut

sub validateRegex {
	my ($class, $value, $regex, $negate) = @_;

	return 0 unless defined $value;
	return 0 if ref $value;
	return 0 unless defined $regex;

	if ($negate) {
		return 1 unless $value =~ m/$regex/;
	}
	else {
		return 1 if $value =~ m/$regex/;
	}

	return 0;
}

=head2 validateValue

Validate that a value is valid for the details given

=head3 Arguments

* The value we're validating.
* The validation that we're validating against OR an arrayref of multiple acceptable validations to
validate against.
* Any additional arguments for that validator.

Most validation subroutines only require a single argument to be passed in - the value itself. Some
however require more details in order to be validated correctly. Examples:

### Returns true because the value passed is a positive integer.
my $isValid = ConvoTreeEngine::Validation->validateValue('23', 'positiveInt');

### This will return true because it will validate as an element of the "note" type.
my $isValid = ConvoTreeEngine::Validation->validateValue({
	note  => 'This is a note',
	arbit => 'Arbitrary data',
}, 'singleElement', 'note');

### Both of these will return true because the value is an array containing values that are either
### positive integers or strings.
my $isValid = ConvoTreeEngine::Validation->validateValue(
	['23', 'taco'],
	'arrayOf(positiveInt,string)',
);
my $isValid = ConvoTreeEngine::Validation->validateValue(
	['23', 'taco'],
	'arrayOf',
	'positiveInt',
	'string',
);

### This will return true because the value being passed is either a positive integer or a hashref.
my $isValid = ConvoTreeEngine::Validation->validateValue('23', ['positiveInt', 'hash']);

=cut

my @failures;
my $nested = 0;
sub validateValue {
	my $class      = shift;
	my $value      = shift;
	my $validation = shift;
	my @additional = @_;

	if ($nested == 0) {
		@failures = ();
	}
	$nested++;

	$validation = [$validation] unless ref $validation;

	my $isValid;
	foreach my $v (@$validation) {
		if ($v =~ m/^arrayOf\((.*)\)\z/) {
			my $patterns = $1;
			my @patterns = split m/\s*,\s*/, $patterns;
			foreach my $pattern (@patterns) {
				next if $pattern eq '1';
				ConvoTreeEngine::Exception::Input->throw(
					error => "Validation '$pattern' does not exist",
				) unless $validations{$pattern};
			}
			$isValid = $arrayOf->($class, $value, @patterns);
		}
		else {
			my @additional = @additional;
			if ($v =~ m/^([^\(]+)\((.*)\)\z/) {
				my $validator = $1;
				my $args = $2;
				my @args = split m/\s*,\s*/, $args;
				@additional = (@args, @additional);
				$v = $validator;
			}

			ConvoTreeEngine::Exception::Input->throw(
				error => "Validation '$v' does not exist",
			) unless $validations{$v};

			my $ref = ref $validations{$v} || '';
			if ($ref eq 'CODE') {
				$isValid = $validations{$v}->($class, $value, @additional);
			}
			elsif ($ref eq '') {
				### If it's just a string, assume it's regex
				$isValid = $class->validateRegex($value, $validations{$v}, @additional);
			}
		}
		if ($isValid) {
			$nested--;
			return $isValid;
		}
	}

	my $displayValue = ref $value ? JSON::encode_json($value) : $value;
	my $failure = "* Value(s) '" . $displayValue . "' did not meet validation(s) '" . join("', '", @$validation) . "'";
	if (@additional) {
		$failure .= " with additional args: '" . join("', '", @additional) . "'";
	}
	push @failures, $failure;

	$nested--;
	return $isValid;
}

sub _validation_failures {
	my $class = shift;

	return join "\n", @failures;
}

1;