package ConvoTreeEngine::Validation;

use strict;
use warnings;

use ConvoTreeEngine::Object;

our $STRICT_ITEM_TYPE_VALIDATION = 1;
my %elementTypeValidation;

sub new {
	my $class = shift;
	my $args  = ConvoTreeEngine::Object->_prep_args(@_);

	$args->{details} = [] if $args->{details};

	return bless $args, $class;
}

=head2 ignore

No validation necessary; always pass.

=cut

my $ignore = sub {
	my ($self, $value) = @_;
	return $self->pass('Value passes validation for type "ignore"', $value);
};

=head2 undefined

Return true if the value is not defined

=cut

my $undefined = sub {
	my ($self, $value) = @_;
	return $self->fail('A defined value does not pass validation for type "undefined"', $value) if defined $value;
	return $self->pass('An undefined value passes validation for type "undefined"');
};

=head2 boolean

Returns true if the value is 0, 1, undef, or a JSON::Boolean object

=cut

my $boolean = sub {
	my ($self, $value) = @_;
	return $self->pass('An undefined value passes validation for type "boolean"') if !defined $value;
	if (ref $value) {
		return $self->pass('A JSON::Boolean object passes validation for type "boolean"') if $value->isa('JSON::Boolean');
		return $self->fail('A reference or blessed object does not pass validation for type "boolean"', $value);
	}
	return 1 if $self->validateRegex($value, '^[01]\z');
	return $self->fail('Did not pass validation for type "boolean"', $value);
};

=head2 hash

Returns true if the value is a hashref

=cut

my $hash = sub {
	my ($self, $value) = @_;
	return $self->fail('Did not pass validation for type "hash"', $value) unless (ref $value || '') eq 'HASH';
	return $self->pass('Passed validation for type "hash"', $value);
};

=head2 array

Returns truue if the value is an arrayref

=cut

my $array = sub {
	my ($self, $value) = @_;
	return $self->fail('Did not pass validation for type "array"', $value) unless (ref $value || '') eq 'ARRAY';
	return $self->pass('Passed validation for type "array"', $value);
};

=head2 namecat

Returns true if the calue is a valid namecat

A namecat must validate as 'dashWords' followed by a colon, followed by 'dashWords'. Either
instance of 'dashWords' can instead be an empty string, but not both.

NOTE that while there are instances where a namecat can be undefined, a undefined value DOES
NOT validate as a namecat.

=cut

my $namecat = sub {
	my ($self, $value) = @_;
	return 0 if $self->validateRegex($value, ':', 1);
	my ($cat, $name, @other) = split m/:/, $value;
	return $self->fail('A namecat can only have one ":" character', $value) if @other;
	return 0 if $cat  && !$self->validateValue($cat,  'dashWords');
	return 0 if $name && !$self->validateValue($name, 'dashWords');
	return 1;
};

=head2 elementList

An element list can be any of the following:

* A positive integer
* A namecat
* An arrayref containing at least zero elements, all of which are positive integers or namecats

=cut

my $elementList = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, ['positiveInt', 'namecat', 'arrayOf(positiveInt,namecat)']);
	return 1;
};

=head2 itemTextNested

Nested item text is an array of two or three elements. The first array element, if defined,
will be a string of classes to apply to an HTML span. The second, if defined, is the text
for that span - either as a string, or as an array of itemTextNested arrays. If the second
is defined, there will not be a third array element; otherwise the third element will be a
variable name, the value of which will be populated as the text of the span.

=cut

my $itemTextNested = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'array');
	### The first element will either be undefined or a string of dashWords
	return 0 if defined $value->[0] && !$self->validateValue($value->[0], 'dashWords');
	### The second element must be undefined, or a string, or another item block
	if (defined $value->[1]) {
		return 0 unless $self->validateValue($value->[1], ['string', 'arrayOf(1,itemTextNested)']);
		### If it is defined, there cannot be a third element
		return $self->fail('If the second element in a nested item text array is defined, it may only have a total of two elements', $value) unless @$value == 2;
	}
	else {
		### If the second element is undefined, the third must match the validation for a variable name
		return $self->fail('A nested item text array must have two or three elements', $value) unless @$value == 3;
		return 0 unless $self->validateValue($value->[2], 'variableName');
	}
	return 1;
};

=head2 itemTextHash

A hash of information for producing item text.

=cut

my $itemTextHash = sub {
	my ($self, $value) = @_;
	return $self->validateValue($value, 'hashOf', {
		speaker => [0, 'dashWords'],
		text    => [1, ['string', 'arrayOf(1,itemTextNested)']],
		classes => [0, 'dashWords'],
		hover   => [0, 'string'],
		frame   => [0, 'dashWords']
	});
};

=head2 singleElement

Given the JSON value for an element and it's type, validate that it matches what's expected.

=cut

my $singleElement = sub {
	### Return true if the value has the structure of a single element
	my ($self, $value, $type) = @_;
	return 0 unless $self->validateValue($value, 'hash');
	$type ||= $value->{type};
	return $self->fail('An element must have a type', $value) unless $type;
	return $self->fail("Element type '$type' does not exist", $value) unless $elementTypeValidation{$type};
	### Make sure that we're ignoring type, if present
	local $elementTypeValidation{$type}{type} ||= [0, 'ignore'];
	return $self->validateValue($value, 'hashOf', $elementTypeValidation{$type});
};
my $conditionString = sub {
	### A string of text
	my ($self, $value) = @_;
	return $self->pass('An undefined value passes validation for type "conditionString"') if !defined $value;
	return $self->fail('Validation type "conditionString" cannot be a reference', $value) if ref $value;
	return $self->fail('Validation type "conditionString" cannot be an empty string', $value) if !length $value;

	### Set aside quoted strings that might contain special characters
	my @quoted = $value =~ m/'[^']*'|"[^"]*"/g;
	my $valueMod = $value =~ s/'[^']*'|"[^"]*"/\x00/gr;

	### If there's an extra quote at the end, the string we were passed was malformed
	return $self->fail('String has an unmatched quotation mark', $value) if $valueMod =~ m/['"]/;

	my @parts = split m/[&|]/, $valueMod;
	foreach my $part (@parts) {
		$part =~ s/^\s+|\s+$//g;
		### Put the quoted bits back
		my @quoted_count = $part =~ m/\x00/g;
		if (@quoted_count) {
			my @pieces = split m/\x00/, $part;
			if ($part =~ m/\x00$/) {
				push @pieces, '';
			}
			$part = shift @pieces;
			while (@pieces) {
				$part .= shift(@quoted) . shift(@pieces);
			}
		}

		if ($part =~ m/^!?seen\s*:(.*)$/i) {
			### A part can also be the string "seen:" followed by an identifier for an element (indicating that that element has already been seen by the user)
			### If it's preceeded by an exclamation point, that means that it hasn't been seen
			my $seen = $1;
			$seen =~ s/^\s+|\s+$//g;
			return $self->fail('A "seen" condition must be followed by a valid element identifier', $part) unless $self->validateValue($seen, ['positiveInt', 'namecat']);
			next;
		}
		elsif ($part =~ m/^!?function\s*:(.*)$/i) {
			### A part can indicate the name of a javascript function that will return a true or false value
			my $func = $1;
			$func =~ s/^\s+|\s+$//g;
			return 0 unless $self->validateValue($func, 'word');
			next;
		}
		elsif ($part =~ m/^!?first$/i) {
			### A part can be the word "first" indicating that no options previous to this one have returned true
			next;
		}

		### Each part contains a variable name, an operator, and a condition
		my ($operator) = $part =~ m/!==|[!><=]=|[=><]/g;
		return $self->fail('Condition string does not have an operator', $part) unless $operator;
		my ($varName, $cond) = split m/$operator/, $part;
		$varName =~ s/^\s+|\s+$//g;
		$cond =~ s/^\s+|\s+$//g;

		### If it starts with an exclamation point, strip that out
		$varName = substr($varName, 1) if substr($varName, 0, 1) eq '!';
		return 0 unless $self->validateValue($varName, 'variableName');
		return 0 unless $self->validateValue($cond, 'string');
		if ($operator =~ m/[<>]|==/) {
			### If the operator is specific to numbers, make sure that the condition is a number
			return 0 unless $self->validateValue($cond, 'number');
		}
		else {
			if ($cond =~m/^(['"])(.*)\1\s*\z/) {
				### If it's a quoted string, just take what's in the quotes
				$cond = $2;
				return 0 unless $self->validateValue($cond, 'string');
			}
			else {
				### Otherwise make sure that it has no spaces or special characters
				return 0 unless $self->validateValue($cond, 'word');
			}
		}
	}
	return $self->pass('Valid condition string', $value);
};
my $condition = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, ['undefined', 'conditionString', 'conditionBlock', 'arrayOf(condition)']);
	return 1;
};
my $conditionBlock = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'hashOf', {
		not => [0, 'condition'],
		and => [0, 'condition'],
		or  => [0, 'condition'],
		xor => [0, 'condition'],
	});
	### Make sure it contains at least one of the above keys
	return $self->pass('Valid condition block', $value) unless scalar keys %$value == 0;
	return $self->fail('Invalid condition block', $value);
};
my $ifConditionBlock = sub {
	### the value will be an array
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'array');
	### The first element will either be undefined or a condition string
	return 0 unless $self->validateValue($value->[0], 'condition');
	return $self->fail('If condition blocks should be an array of one, two, or three elements', $value) if @$value > 3;
	return $self->pass('Valid condition block with one element', $value) if @$value == 1;
	### If the second element is present, it should be an element ID or an array of element IDs
	return 0 unless $self->validateValue($value->[1], ['undefined', 'elementList']);
	return 0 if @$value == 3 && !$self->validateValue($value->[2], 'string');
	return $self->pass('Valid condition block with two or three elements', $value);
};
my $variableUpdates = sub {
	### Returns true if given a hash of variable names to strings (or undefineds)
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'hash');
	foreach my $key (keys %$value) {
		return 0 unless $self->validateValue($key, 'variableName');
		### The strings for updating numerical values could be parsed, but if they failed, we'd
		### just check them against "string" anyway, and they'd pass that, so there's no point.
		return 0 unless $self->validateValue($value->{$key}, ['string', 'undefined']);
		if ($value->{$key} =~ m/^[+\*\/-]=/ && !$self->validateValue(substr($value->{$key}, 2), 'number')) {
			return $self->fail('"VariableUpdate" operator indicates a number, but the value is not a number', $value->{$key});
		}
	}
	return 1;
};
my $choice = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'hashOf', {
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
	return $self->fail("Element '$value->{element}' does not exist", $value) unless $element;
	return $self->fail("Element '$value->{element}' is not type 'item' or 'raw'", $value) unless $element->type eq 'item' || $element->type eq 'raw';
	return 1;
};
my $randomPath = sub {
	my ($self, $value) = @_;
	return 0 unless $self->validateValue($value, 'array');
	return $self->fail('random paths must be an array of two elements', $value) unless @$value == 2;
	return 0 unless $self->validateValue($value->[0], 'positiveInt');
	return 0 unless $self->validateValue($value->[1], 'elementList');
	return 1;
};
my $arrayOf = sub {
	my ($self, $value, @patterns) = @_;
	return 0 unless $self->validateValue($value, 'array');
	if ($patterns[0] eq '1') {
		shift @patterns;
		return $self->fail('Array cannot be empty') unless @$value;
	}
	return $self->fail('No patterns given to match array elements against') unless @patterns;
	foreach my $deep (@$value) {
		return 0 unless $self->validateValue($deep, \@patterns);
	}
	return 1;
};
my $hashOf = sub {
	my ($self, $value, @patterns) = @_;
	return 0 unless $self->validateValue($value, 'hash');
	return $self->fail('No patterns given to match hash against') unless @patterns;
	my %flags;
	if (!ref $patterns[-1]) {
		my $flags = shift @patterns;
		return $self->fail('No patterns given to match hash against') unless @patterns;
		%flags = map {$_ => 1} split m/\s*,\s*/, $flags;
	}
	my $match = 0;
	PATTERN:
	foreach my $pattern (@patterns) {
		next PATTERN unless $self->validateValue($pattern, 'hash');
		unless ($flags{keep_extra}) {
			### Fail out if there are extra keys
			foreach my $key (keys %$value) {
				next PATTERN unless $pattern->{$key};
			}
		}
		KEY:
		foreach my $key (keys %$pattern) {
			next PATTERN unless $self->validateValue($pattern->{$key}, 'array');
			### If it's not present and not required, that's fine
			next KEY unless $pattern->{$key}[0] && exists $value->{$key};
			next PATTERN unless exists $value->{$key};
			### Make sure it passes validation for that element type
			my $validation = $pattern->{$key}[1];
			my @args = ($value->{$key});
			if (scalar @{$pattern->{$key}} > 2) {
				push @args, @{$pattern->{$key}}[2..$#{$pattern->{$key}}];
			}
			next PATTERN unless $self->validateValue(@args, $validation);
		}
		$match = 1;
		last PATTERN;
	}
	return $match;
};

my %validations = (
	ignore           => $ignore,
	undefined        => $undefined,
	boolean          => $boolean,
	hash             => $hash,
	array            => $array,
	variableName     => '^[a-zA-Z0-9_.]+\z', # A pattern we're specifcally using for variable names
	words            => '^(?:[a-zA-Z0-9_]+ ?)+\b\z', # A string of words separated by single spaces
	dashWords        => '^(?:[a-zA-Z0-9_]+[ -]?)+\b\z', # A string of words separated by either single spaces or single hyphens
	word             => '^[a-zA-Z0-9_]+\z', # A single word containg letters numbers and/or underscores
	string           => '^[^\x00-\x09\x0B\x0C\x0E-\x1F\x7F]*$', # No control characters other than "Line Feed" and "Carriage Return"
	positiveInt      => '^[1-9][0-9]*\z', # Looks like a positive integer
	nonNegInt        => '^[0-9]+\z', # Looks like a non-negative integer
	number           => '^(-?[1-9][0-9]*|0)(\.[0-9]+)?\z', # Looks like a number
	uuid             => '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z',
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
		delay    => [0, 'nonNegInt'],
		prompt   => [0, ['boolean', 'string', 'arrayOf(1,itemTextNested)', 'itemTextHash']],
		arbit    => [0, 'ignore'],
	},
	note     => {
		note  => [1, 'string'],
		arbit => [0, 'ignore'],
	},
	raw      => {
		html   => [1, 'string'],
		delay  => [0, 'nonNegInt'],
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
		delay   => [0, 'nonNegInt'],
		classes => [0, 'dashWords'],
		keep    => [0, {enum => [qw/0 1 2/]}],
		arbit   => [0, 'ignore'],
	},
	display  => {
		mine      => [0, 'hash'],
		all       => [0, 'hash'],
		wipe_mine => [0, 'boolean'],
		wipe_all  => [0, 'boolean'],
		delay     => [0, 'nonNegInt'],
		arbit     => [0, 'ignore'],
	},
	do       => {
		function => [1, 'word'],
		args     => [0, 'ignore'],
		delay    => [0, 'nonNegInt'],
		stop     => [0, 'boolean'],
		arbit    => [0, 'ignore'],
	},
	elements => {
		get   => [0, 'elementList'],
		queue => [0, 'elementList'],
		drop  => [0, 'boolean'],
		jump  => [0, 'elementList'],
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
	my $invocant  = shift;
	my $json      = shift;
	my $type      = shift;

	my $self = ref $invocant ? $invocant : $invocant->new();

	unless (ref $json) {
		$json = JSON::decode_json($json);
	}

	my $isValid = $self->validateValue($json, 'singleElement', $type);
	unless ($isValid) {
		##### TODO: details output?
		my $failures = $self->listFailures;
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
	my ($invocant, $value, $regex, $negate) = @_;

	my $self = ref $invocant ? $invocant : $invocant->new();

	return $self->fail('cannot regex match an undefined value') unless defined $value;
	return $self->fail('cannot regex match a reference', $value) if ref $value;
	return $self->fail('cannot regex match if no regex given') unless defined $regex;

	if ($negate) {
		return $self->pass("Value does not match m/$regex/", $value) unless $value =~ m/$regex/;
		return $self->fail("Value matches m/$regex/", $value);
	}
	else {
		return $self->pass("Value matches m/$regex/", $value) if $value =~ m/$regex/;
		return $self->fail("Value does not match m/$regex/", $value);
	}
}

=head2 validateEnum

Given a value and an enumerated list, ensure that the value is present in the enumerated list.

=cut

sub validateEnum {
	my ($invocant, $value, $list) = @_;

	my $self = ref $invocant ? $invocant : $invocant->new();

	return $self->fail('cannot enum match an undefined value') unless defined $value;
	return $self->fail('cannot enum match a reference', $value) if ref $value;
	return $self->fail('cannot enum match if no enumerated list is given') unless defined $list;

	$list = [$list] unless ref $list;

	return $self->fail('can only enum match against an arrayref of strings') unless $self->validateValue($list, 'arrayOf(1,string)');

	foreach my $listItem (@$list) {
		return $self->pass("Value matches '$listItem'") if $value eq $listItem;
	}

	return $self->fail("Value did not match any of: '" . join("', '", sort(@$list)) . "'", $value);
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

sub validateValue {
	my $invocant   = shift;
	my $value      = shift;
	my $validation = shift;
	my @additional = @_;

	my $self = ref $invocant ? $invocant : $invocant->new();

	if ($self->nested == 0) {
		$self->reset;
	}
	$self->nested(1);

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
			$isValid = $arrayOf->($self, $value, @patterns);
			if ($isValid) {
				$self->pass('Passed validation for "arrayOf" with patterns: [' . join(@patterns) . ']');
			}
			else {
				$self->fail('Did not pass validation for "arrayOf" with patterns: [' . join(@patterns) . ']', $value);
			}
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

			my $validator = $v;
			my $ref = ref $validator || '';
			if (ref eq '') {
				ConvoTreeEngine::Exception::Input->throw(
					error => "Validation '$v' does not exist",
				) unless $validations{$v};

				$validator = $validations{$v};
				$ref = ref $validator || '';
			}

			if ($ref eq 'CODE') {
				$isValid = $validations{$v}->($self, $value, @additional);

				my $stringAdditional = '';
				if (@additional) {
					$stringAdditional .= " with additional args: '" . join("', '", @additional) . "'";
				}

				if ($isValid) {
					$self->pass("Passed validation of type '$v'$stringAdditional", $value);
				}
				else {
					$self->pass("Did not pass validation of type '$v'$stringAdditional", $value);
				}
			}
			elsif ($ref eq 'HASH') {
				foreach my $key (keys %$validator) {
					if ($key eq 'regex') {
						$isValid = $self->validateRegex($value, $validator->{$key}, @additional);
					}
					elsif ($key eq 'enum') {
						$isValid = $self->validateEnum($value, $validator->{$key}, @additional);
					}
					last unless $isValid;
				}
			}
			elsif ($ref eq '') {
				### If it's just a string, assume it's regex
				$isValid = $self->validateRegex($value, $validations{$v}, @additional);
			}
		}
		if ($isValid) {
			$self->nested(-1);
			return $isValid;
		}
	}

	my $displayValue = ref $value ? JSON::encode_json($value) : $value;
	my $failure = "Value(s) '" . $displayValue . "' did not meet validation(s) '" . join("', '", @$validation) . "'";
	if (@additional) {
		$failure .= " with additional args: '" . join("', '", @additional) . "'";
	}
	$self->addFailure($failure);

	$self->nested(-1);
	return $isValid;
}

sub details {
	return shift->{details};
}
sub addDetail {
	my $self    = shift;
	my $message = shift;

	if ($self->{details}) {
		push @{$self->{details}}, $message;
	}

	return;
}

sub nested {
	my $self = shift;
	my $add  = shift || 0;

	$self->{nested} //= 0;
	$self->{nested} += $add;

	return $self->{nested};
}

sub reset {
	my $self = shift;
	$self->{failures} = [];
	$self->{details} &&= [];
	return;
}

sub failures {
	my $self = shift;
	return $self->{failures} ||= [];
}
sub addFailure {
	my $self    = shift;
	my $message = shift;

	$self->{failures} ||= [];
	push @{$self->{failures}}, $message;
}

sub fail {
	my $self = shift;

	if ($self->details) {
		my $message = shift;
		my $value   = shift;

		my $detail = 'Fail: ' . $message . '.';
		if (defined $value) {
			my $displayValue = ref $value ? JSON::encode_json($value) : $value;
			$detail .= " Value: $displayValue";
		}

		$self->addDetail($detail);
	}

	return 0;
}

sub pass {
	my $self = shift;

	if ($self->details) {
		my $message = shift;
		my $value   = shift;

		my $detail = 'Pass: ' . $message . '.';
		if (defined $value) {
			my $displayValue = ref $value ? JSON::encode_json($value) : $value;
			$detail .= " Value: $displayValue";
		}

		$self->addDetail($detail);
	}

	return 1;
}

sub info {
	my $self = shift;

	if ($self->details) {
		my $message = shift;
		my $value   = shift;

		my $detail = 'Info: ' . $message . '.';
		if (defined $value) {
			my $displayValue = ref $value ? JSON::encode_json($value) : $value;
			$detail .= " Value: $displayValue";
		}

		$self->addDetail($detail);
	}

	return;
}

sub listFailures {
	my $self = shift;
	return '* ' . join("\n* ", @{$self->failures});
}

1;