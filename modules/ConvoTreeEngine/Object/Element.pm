package ConvoTreeEngine::Object::Element;

use parent 'ConvoTreeEngine::Object';

use strict;
use warnings;

use JSON;

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

	$args->{json} = $invocant->_validate_json($args->{json}, $args->{type});

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
		$args->{json} = $self->_validate_json($args->{json}, $self->type);
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

#================#
#== Validation ==#
#================#

our $STRICT_ITEM_TYPE_VALIDATION = 1;
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
		return 1 if $class->_validate_regex($value, '^[01]\z');
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
		### A namecat must validate as 'words' followed by a colon, followed by 'words'. Either instance of 'words' can instead be an empty string, but not both
		### NOTE that while a namecat can be undefined, a undefined value DOES NOT validate as a namecat
		my ($class, $value) = @_;
		return 0 if $class->_validate_regex($value, ':', 1);
		my ($cat, $name, @other) = split m/:/, $value;
		return 0 if @other;
		return 0 if $cat  && !$class->_validate_value($cat,  'words');
		return 0 if $name && !$class->_validate_value($name, 'words');
		return 1;
	};
	my $elementList = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, ['positiveInt', 'namecat', 'arrayOf(positiveInt,namecat)']);
		return 1;
	};
	my $itemTextNested = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will either be undefined or a string of words
		return 0 if defined $value->[0] && !$class->_validate_value($value->[0], 'words');
		### The second element must be undefined, or a string, or another item block
		if (defined $value->[1]) {
			return 0 unless $class->_validate_value($value->[1], ['string', 'arrayOf(1,itemTextNested)']);
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
	my $itemTextHash = sub {
		my ($class, $value) = @_;
		return $class->_validate_value($value, 'hashOf', {
			speaker => [0, 'words'],
			text    => [1, ['string', 'arrayOf(1,itemTextNested)']],
			classes => [0, 'words'],
			hover   => [0, 'string'],
		});
	},
	my $singleElement = sub {
		### Return true if the value has the structure of a single element
		my ($class, $value, $type) = @_;
		return 0 unless defined $value;
		return 0 unless (ref $value || '') eq 'HASH';
		$type ||= $value->{type};
		return 0 unless $type;
		return 0 unless $typeValidation{$type};
		### Make sure that we're ignoring type, if present
		local $typeValidation{$type}{type} ||= [0, 'ignore'];
		return $class->_validate_value($value, 'hashOf', $typeValidation{$type});
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
				return 0 unless $class->_validate_value($seen, ['positiveInt', 'namecat']);
				next;
			}
			elsif ($part =~ m/^!?function:(.*)$/i) {
				### A part can indicate the name of a javascript function that will return a true or false value
				my $func = $1;
				return 0 unless $class->_validate_value($func, 'word');
				next;
			}
			elsif ($part =~ m/^!?first\z/i) {
				### A part can be the word "first" indicating that no options previous to this one have returned true
				next;
			}
			### Each part contains a variable name, an operator, and a condition
			my $operator = do {
				$part =~ m/([!><]=|[=><])/;
				$1;
			};
			return 0 unless $operator;
			my ($varName, $cond, @other) = split m/\s*$operator\s*/, $part;
			### If it starts with an exclamation point, strip that out
			$varName = substr($varName, 1) if substr($varName, 0, 1) eq '!';
			return 0 if @other;
			return 0 unless $class->_validate_value($varName, 'variableName');
			if ($operator =~ m/[<>]/) {
				### If the operator is specific to numbers, make sure that the condition is a number
				return 0 unless $class->_validate_value($cond, 'number');
			}
			else {
				if ($cond =~m/^(['"])(.*)\1\s*\z/) {
					### If it's a quoted string, just take what's in the quotes
					$cond = $2;
					return 0 unless $class->_validate_value($cond, 'string');
				}
				else {
					### Otherwise make sure that it has no spaces or special characters
					return 0 if $cond =~ m/\s/;
					return 0 unless $class->_validate_value($cond, 'word');
				}
			}
		}
		return 1;
	};
	my $conditionBlock = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'hashOf', {
			and => [0, ['conditionString', 'conditionBlock', 'arrayOf(conditionString,conditionBlock)']],
			or  => [0, ['conditionString', 'conditionBlock', 'arrayOf(conditionString,conditionBlock)']],
			xor => [0, ['conditionString', 'conditionBlock', 'arrayOf(conditionString,conditionBlock)']],
		});
		### Make sure it contains at least one of the above keys
		return 1 unless scalar keys %$value == 0;
	};
	my $singleCondition = sub {
		### the value will be an array
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		### The first element will either be undefined or a condition string
		return 0 unless $class->_validate_value($value->[0], ['undefined', 'conditionString', 'conditionBlock']);
		return 0 if @$value > 2;
		return 1 unless @$value == 2;
		### If the second element is present, it should be an element ID or an array of element IDs
		return 0 unless $class->_validate_value($value->[1], 'elementList');
		return 1;
	};
	my $variableUpdates = sub {
		### Returns true if given a hash of variable names to strings (or undefineds)
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'hash');
		foreach my $key (keys %$value) {
			return 0 unless $class->_validate_value($key, 'variableName');
			### The strings for updating numerical values could be prased, but if they failed, we'd
			### just check them against "string" anyway, and they'd pass that, so there's no point.
			return 0 unless $class->_validate_value($value->{$key}, ['string', 'undefined']);
			return 0 if $value->{$key} =~ m/^[+\*\/-]=/ && !$class->_validate_value(substr($value->{$key}, 2), 'number');
		}
		return 1;
	};
	my $choice = sub {
		my ($class, $value) = @_;
		return 0 unless $class->_validate_value($value, 'hashOf', {
			cond    => [0, ['undefined', 'conditionString', 'conditionBlock']],
			element => [1, ['positiveInt', 'namecat']],
			then    => [0, 'elementList'],
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
		return 0 unless $class->_validate_value($value, 'array');
		return 0 unless @$value == 2;
		return 0 unless $class->_validate_value($value->[0], 'positiveInt');
		return 0 unless $class->_validate_value($value->[1], 'elementList');
		return 1;
	};
	my $arrayOf = sub {
		my ($class, $value, @patterns) = @_;
		return 0 unless $class->_validate_value($value, 'array');
		if ($patterns[0] eq '1') {
			shift @patterns;
			return 0 unless @$value;
		}
		return 0 unless @patterns;
		foreach my $deep (@$value) {
			return 0 unless $class->_validate_value($deep, \@patterns);
		}
		return 1;
	};
	my $hashOf = sub {
		my ($class, $value, @patterns) = @_;
		return 0 unless $class->_validate_value($value, 'hash');
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
			next PATTERN unless $class->_validate_value($pattern, 'hash');
			unless ($flags{keep_extra}) {
				### Fail out if there are extra keys
				foreach my $key (keys %$value) {
					next PATTERN unless $pattern->{$key};
				}
			}
			KEY:
			foreach my $key (keys %$pattern) {
				next PATTERN unless $class->_validate_value($pattern->{$key}, 'array');
				### If it's not present and not required, that's fine
				next KEY unless $pattern->{$key}[0] && exists $value->{$key};
				next PATTERN unless exists $value->{$key};
				### Make sure it passes validation for that element type
				my $validation = $pattern->{$key}[1];
				my @args = ($value->{$key});
				if (scalar @{$pattern->{$key}} > 2) {
					push @args, @{$pattern->{$key}}[2..$#{$pattern->{$key}}];
				}
				next PATTERN unless $class->_validate_value(@args, $validation);
			}
			$match = 1;
			last PATTERN;
		}
		return $match
	};

	my %validations = (
		ignore          => $ignore,
		undefined       => $undefined,
		boolean         => $boolean,
		hash            => $hash,
		array           => $array,
		variableName    => '^[a-zA-Z0-9_.]+\z', # What we expect from a javascript variable name
		words           => '^(?:[a-zA-Z0-9_]+[ -]?)+\b\z', # A string of words separated by either single spaces or single hyphens
		word            => '^[a-zA-Z0-9_]+\z', # A single word containg letters numbers and/or underscores
		string          => '^[^\x00-\x09\x0B\x0C\x0E-\x1F\x7F]*$', # No control characters other than "Line Feed" and "Carriage Return"
		positiveInt     => '^[1-9][0-9]*\z', # Looks like a positive integer
		number          => '^(-?[1-9][0-9]*|0)(\.[0-9]+)?\z', # Looks like a number
		namecat         => $namecat,
		elementList     => $elementList,
		itemTextNested  => $itemTextNested,
		itemTextHash    => $itemTextHash,
		singleElement   => $singleElement,
		conditionString => $conditionString,
		conditionBlock  => $conditionBlock,
		singleCondition => $singleCondition,
		variableUpdates => $variableUpdates,
		choice          => $choice,
		randomPath      => $randomPath,
		arrayOf         => $arrayOf,
		hashOf          => $hashOf,
	);

=head2 typeValidation

A hashref of element types. For each type, there will be a hashref of key/value pairs in that type. The
value will be an array with two elements - Boolean representing if it's required, and eith a string or
an array of strings indicating validators for what can be present.

=cut

	%typeValidation = (
		item     => {
			text     => [1, 'itemTextHash'],
			textx    => [0, 'itemTextHash'],
			function => [0, 'word'],
			delay    => [0, 'positiveInt'],
			prompt   => [0, 'boolean'],
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
			cond  => [1, 'arrayOf(1,singleCondition)'],
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
			get   => [1, 'elementList'],
			arbit => [0, 'ignore'],
		},
		series   => {
			series     => [1, 'elementList'],
			additional => [0, 'elementList'],
			arbit      => [0, 'ignore'],
		},
		random   => {
			paths    => [1, 'arrayOf(1,randomPath)'],
			function => [1, 'word'],
			arbit    => [0, 'ignore'],
		},
	);

=head2 _validate_json

Given either a JSON blob or a hashref, and an element type, validate that the data given matches that
type.

=cut

	sub _validate_json {
		my $invocant = shift;
		my $json     = shift;
		my $type     = shift;

		my $class = ref $invocant || $invocant;

		unless (ref $json) {
			$json = JSON::decode_json($json);
		}

		my $isValid = $class->_validate_value($json, 'singleElement', $type);
		unless ($isValid) {
			my $failures = $class->_validation_failures;
			ConvoTreeEngine::Exception::Input->throw(
				error => "Validation for Element JSON did not pass:\n$failures",
				code  => 400,
			);
		}

		return JSON::encode_json($json);
	}

=head2 _validate_regex

Verify that a value is a scalar and matches (or does not match) a regular expression.

Note: Under the vast majority of circumstances, this should be called with an "if" and not an
"unless", as regardless of whether we're negating, this will return fales if the value passed
is undefined, or if it is not a string.

=head3 Arguments

* $value  - The value we're validating
* $regex  - The regular expression we're validating against
* $negate - Boolean; true if we want to NOT match the regular expression

=cut

sub _validate_regex {
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

=head2 _validate_value

Validate that a value is valid for the details given

=head3 Arguments

* The value we're validating.
* The validation that we're validating against OR an arrayref of multiple acceptable validations to
  validate against.
* Any additional arguments for that validator.

Most validation subroutines only require a single argument to be passed in - the value itself. Some
however require more details in order to be validated correctly. Examples:

    ### Returns true because the value passed is a positive integer.
    my $isValid = ConvoTreeEngine::Object::Element->_validate_value('23', 'positiveInt');

    ### This will return true because it will validate as an element of the "note" type.
    my $isValid = ConvoTreeEngine::Object::Element->_validate_value({
        note  => 'This is a note',
        arbit => 'Arbitrary data',
    }, 'singleElement', 'note');

    ### Both of these will return true because the value is an array containing values that are either
    ### positive integers or strings.
    my $isValid = ConvoTreeEngine::Object::Element->_validate_value(
        ['23', 'taco'],
        'arrayOf(positiveInt,string)',
    );
    my $isValid = ConvoTreeEngine::Object::Element->_validate_value(
        ['23', 'taco'],
        'arrayOf',
        'positiveInt',
        'string',
    );

    ### This will return true because the value being passed is either a positive integer or a hashref.
    my $isValid = ConvoTreeEngine::Object::Element->_validate_value('23', ['positiveInt', 'hash']);

=cut

	my @failures;
	my $nested = 0;
	sub _validate_value {
		my $invocant   = shift;
		my $value      = shift;
		my $validation = shift;
		my @additional = @_;

		my $class = ref $invocant || $invocant;

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
					$isValid = $class->_validate_regex($value, $validations{$v}, @additional);
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
		my $invocant = shift;

		return join "\n", @failures;
	}
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
			my $isValid = $invocant->_validate_value($args->{$key}, 'words');
			unless ($isValid) {
				my $failures = $invocant->_validation_failures;
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
		if ($jsonRef->{additional}) {
			if (ref $jsonRef->{additional}) {
				push @elements, @{$jsonRef->{additional}};
			}
			else {
				push @elements, $jsonRef->{additional};
			}
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
		if ($verify_exists && !$verified{$id}) {
			ConvoTreeEngine::Object::Element->findOrDie({id => $id});
		}
	}

	return @elements;
}

sub doNestedElements {
	my $self = shift;

	if (my @elements = $self->listReferencedElements(1)) {
		my $type = $self->type;
		if ($type eq 'if' || $type eq 'choice' || $type eq 'series' || $type eq 'random') {
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
		elsif ($type eq 'series') {
			$jsonRef->{series} = $element->_sanitize_nesting_arrays($jsonRef->{series}, $args);
			if ($jsonRef->{additional}) {
				$jsonRef->{additional} = $element->_sanitize_nesting_arrays($jsonRef->{additional}, $args);
			}
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