package ConvoTreeEngine::ElementExamples;

use strict;
use warnings;

use JSON;

#======================#
#== Element Examples ==#
#======================#

our %examples;

=head2 Item

Items represent a story element, generally consisting of one or more paragraphs that will be displayed
to the user.

=cut

$examples{item} = {
	text   => [
		[
			'span classes',
			'Span text',
		],
		[
			'span classes',
			[
				[
					'nested span classes',
					'Spans can be nested...'
				],
				[
					'nested span classes',
					'...as deeply as desired'
				],
			],
		],
		[
			undef,
			'If the class is null, the text will not be placed into its own span',
		],
		[
			'span class',
			undef,
			'variableName',
		],
	],
	delay  => '1000',
	prompt => JSON::false,
	stop   => JSON::false,
	arbit  => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "prompt" key is optional. It contains a boolean value indicating whether to prompt before continuing',
			"4" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			"5" => 'For the text blocks, if the second string is null, a third string can include the name of a variable. the value of that variable will be displayed',
		},
	},
};
$examples{item2} = {
	text   => {
		speaker => 'html classes',
		text    => 'A string of text potentially including "quoted bits", _underscored bits_, *starred bits*, and [bracketed bits].',
		classes => 'html classes',
	},
	delay  => '1000',
	prompt => JSON::false,
	stop   => JSON::false,
	arbit  => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "prompt" key is optional. It contains a boolean value indicating whether to prompt before continuing',
			"4" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			"5" => 'If the "text" key is given a hashref, the text in it will be parsed. Quoted bits will be put into a span and given the classes specified under "speaker", underscored bits will be italicized, starred bits will be bolded, and text within bracketed bits will be interpreted as a variable name, and replaced with the value of that variable',
		},
	},
};

=head2 Note

Notes include additional details that will not be displayed to the user. They exist purely for
organizatioal purposes for the creator.

=cut

$examples{note} = {
	note  => 'Arbitrary text that will not be displayed to the user',
	arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
};

=head2 Raw

Raws are blocks that will be interpreted as HTML

=cut

$examples{raw} = {
	html   => 'A string that will be interpreted as HTML and displayed to the user',
	delay  => 1000,
	prompt => JSON::false,
	stop   => JSON::false,
	arbit  => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "prompt" key is optional. It contains a boolean value indicating whether to prompt before continuing',
			"4" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements should stop after this point (identical to a "stop" block)',
		},
	},
};

=head2 Enter and Exit

Enters and exits allow us to display items (or other story elements) within nested blocks.

=cut

$examples{enter} = {
	start => "A string of text to begin a block. Example: '<div class=\"thing\">'\nUntil an \"exit\" block with the same name (or a null name) is reached, content will be placed within this block",
	end   => "A string of text to end a block. Example: '</div>'",
	name  => "One or more space or hyphen-separated words with no special characters except underscores",
	arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
};
$examples{exit} = {
	name  => "One or more space or hyphen-separated words with no special characters except underscores",
	all   => 1,
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "name" key may be undefined (null). If so, it will trigger the exit of any previous "Enter" block',
			"3" => 'The "all" key is optional. It must be a boolean value. If true, it will trigger the exist of ALL previous "Enter" blocks that we might be nested within',
		},
	},
};

=head2 If

Ifs represent a place where the story is able to fork in different directions based on variosu conditions

=cut

$examples{if} = {
	cond  => [
		[
			'var=0',
			[1,2],
		],
	],
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "cond" key will contain an array of arrays',
			"3" => 'Each nested array within the "cond" key will contain either one or two strings',
			"4" => 'The first string will contain one or more sets of a variable name, an operator, and a value',
			"4.a" => 'Variable names may contain letters, numbers, underscores or periods',
			"4.b" => 'Operators may be one of the following: "=", "!=", ">", "<", ">=", "<="',
			"4.c" => 'The value must contain only letters, numbers, and underscores',
			"4.d" => 'If there are multiple sets within within the first string, they will be separated by and ("&") or or ("|") operators',
			"5" => 'The second string (if present) will contain either a single positive integer (representing a single element ID) or an array of positive integers',
			"6" => 'These nested arrays will be processed in order until one of them returns true. At that point, we will follow the path specified by the second value (if any)',
			"6.a" => 'And further condition arrays will be ignored',
			"7" => 'If the first element within a nested array is null, it will be interpreted as returning true',
		},
	},
};

=head2 Assess

Assesses allow the creator to indicate potential future branches of the story - either occurring
immeidately after a specified story element, or after the story has been told to stop.

=cut

$examples{assess} = {
	cond  => [
		'var=0',
		'1',
	],
	after => '1',
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => '"assess" blocks are similar to "if" blocks, except that they will be assessed (In the order they were presented) only after a "stop" block has been reached',
			"2.a" => '...or immediately after any of the blocks specified under the "after" key has been reached',
			"3" => 'The "cond" key will be a single array containing either one or two strings',
			"4" => 'The first string will contain one or more sets of a variable name, an operator, and a value',
			"4.a" => 'Variable names may contain letters, numbers, underscores or periods',
			"4.b" => 'Operators may be one of the following: "=", "!=", ">", "<", ">=", "<="',
			"4.c" => 'The value must contain only letters, numbers, and underscores',
			"4.d" => 'If there are multiple sets within within the first string, they will be separated by and ("&") or or ("|") operators',
			"5" => 'The second string (if present) will contain either a single positive integer (representing a single element ID) or an array of positive integers',
			"6" => 'If the first element within the array is null, it will be interpreted as returning true',
		},
	},
};

=head2 Negate

Negates negate an assess blcok, preventing it from running before it potentially would.

=cut

$examples{negate} = {
	assess_id => "2",
	arbit     => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "assess_id" will contain the ID of an "assess" block or an array with multiple IDs of assess blocks. This negate block will remove the specified assess block from the assess queue',
		},
	},
};

=head2 Stop

Stops indicate that no further queued elements after this point should be displayed. They
are cleared from the queue. At this point, we proceed through any pending assess blocks
in the order in which they were presented.

=cut

$examples{stop} = {
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'Remove all further elements from the queue to be processed; Begin processing elements in the "assess" queue.',
		},
	},
};

=head2 Variable

variables set or update the value of a variable

=cut

$examples{variable} = {
	update => {
		var1 => '1',
		var2 => 'string',
		var3 => '+=1',
	},
	arbit  => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "update" key should be an object containing key value pairs of variable names to what that variable is being set to',
			"3" => 'If the value begins with "+=", "-=", "*=", or "/=", it is assumed that the current value of that variable is a number, and that we will be adding to, subtracting from, multiplying by, or dividing from that value',
		},
	},
};

=head2 Choice

Choices represent an instance where the user has the ability to make a choice in the narrative. There
is the potential for choices to be unavialable based on the values of various variables.

=cut

$examples{choice} = {
	choices => [
		{
			cond     => undef,
			text     => 'display text',
			hover    => 'hover text',
			speaker  => 'html classes',
			classes  => 'html classes',
			showx    => undef,
			classesx => 'more html classes',
			textx    => 'alternate display text',
			hoverx   => 'alternate hover text',
			then     => [1,2],
		},
	],
	arbit  => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "choices" key will contain an array of hashes, containing the following keys',
			"2.a" => '"cond" is the conditions necessary for the option ot be available. undef indicates that ti is always available. If the key is not present, it is always available',
			"2.b" => '"text" is the text that will be displayed for the option. Stars, underscores, brackets, and quotes will be parsed, as in "item" blocks',
			"2.c" => '"hover" is the hover text for the option',
			"2.d" => '"speaker" is html classes that will be used for quoted bits',
			"2.e" => '"classes" is the html classes that will be used to display the option if available',
			"2.f" => '"showx" is the conditions necessary to show the option if it is not available. undef will always show it. If the key is not present, it will not be shown',
			"2.g" => '"classesx" is the classes that will be used to display the option if not available',
			"2.h" => '"textx" is alternative text to display if the option is not available',
			"2.i" => '"hoverx", is alternative hover text to display if the option is not available',
			"2.j" => '"function" is the name of a function that will be run to generate the display for the choice. This will take precidence over "text" if present',
			"2.j.1" => 'The entire condition hash will be passed intot he function as the first and only argument',
			"2.k" => '"arbit" is arbitrary data. The creator can use it for functions, if desired.',
			"2.j" => '"then" is the element or an array of elements that will follow if this option is chosen',
			"3" => 'These choices will be displayed to the user in the order given',
		},
	},
};

=head2 Display

Displays will update the CSS of the page.

##### TODO: Do these replace existing CSS or add to existing CSS?

=cut

$examples{display} = {
	disp  => {
		'css selector' => {
			'text-align'       => 'left',
			'background-color' => '#000000',
		},
	},
	delay => '1000',
	stop  => JSON::false,
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "stop" key is optional. It contains a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			"4" => 'The "dsip" key is a hashref of css selectors to the CSS that will apply to them',
		},
	},
};

=head2 Do

Dos indicate that the specified javascript function should be run

=cut

$examples{do} = {
	function => 'functionName',
	args     => [
		'arg1',
		'arg2',
	],
	delay    => '1000',
	stop     => JSON::false,
	arbit    => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			"4" => 'The function name must be a string of letters, numbers, and underscores',
			"5" => 'The "args" key is optional; If the argument is a string beginning with "var:", it will be assumed that everything following is a variable name. The value of that variable will be used',
		},
	},
};

=head2 Data

Datas indicate that more elements needs to be pulled from the server.

=cut

$examples{data} = {
	get   => [1,2],
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "get" key must contain either a single positive integer (representing a single element ID) or an array of positive integers',
		},
	},
};

=head2 Series

Serieses are a list of consecutive elements, and potentially a list of other related elements.

=cut

$examples{series} = {
	series     => [1,2,3,5],
	additional => [4,6],
	arbit      => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "series" key must contain either a single positive integer (representing a single element ID) or an array of positive integers',
			"3" => 'The "additional" key is optional. It must contain either a single positive integer (representing a single element ID) or an array of positive integers. These elements will not be part of the ordered series, but they will still be returned when the series is requested.',
		},
	},
};

#=======================#
#== Condition Strings ==#
#=======================#

=head2 Basic Conditions

Basic conditions contain a variable, an operator, and a value. For example...

    var=1

...indicates that the value stored int he variable name "var" must be equal to the number or string "1"

The available operators are as follows:

* =  - Indicaes number or string equivalence
* != - Indicates number or string inequivolence
* >= - Indicates that the number is greater than or equal to
* <= - Indicates that the number is lesser than or equal to
* >  - Indicates that the number is greater than
* <  - Indicates that the number is lesser than

If this is preceeded by an exclamation point, return true if the condition would otherwise return false.

If the value that's being compared to is a that contains spaces or other special characters or is an
empty string, that string must be placed in single or double quotes. So the following are acceptable:

    var="a string"
    var="&"
    var=""

=head2 Seen

"Seen" conditions are true or false based on whether an element has been seen. Elements can be referred
to by their ID or their namecat. For example...

    seen:23

...would return true if the user has seen the element with ID 23

"Seen" conditions can begin with an exclamation point. This indicates that we're checking if the element
has NOT been seen.

=head2 Function

"Function" conditions run a javascript function and return true or false based on whether that function
returned true or false. They can begin with an exclamation point, meaning that we're checking for the
option of what the function returns.

=head2 First

"First" conditions are ONLY applicable in "choice" blocks. They return true in a circumstance where none
of the previous conditions have returned true. They can begin with an exclamation point, meaning that
they return true only if there have been other conditions that have returned true.

=head2 "And" and "Or" operators

Multiple conditions can be separated by the "&" (and) and "|" (or) operator. The "or" operator takes
percidence over the "and" operator, so...

    var1>1&var2>1|var1>3

...would be true either if var1 and var2 are grearer than 1, OR if var1 is greater than 3.

If you need conditions more complicated than what this provides, look into using Condition Blocks instead.

=cut

#======================#
#== Condition Blocks ==#
#======================#

=head2 Condition Blocks

Condition blocks are hashrefs that contain one or more of the following keys:

* and
* or
* xor

If a condition block contains more than one of the above keys, it only returns true if ALL of them
return true.

=head3 and

And blocks can contain a condition string, a condition block, or an array of conditions strings/blocks.
They return true if all of the conditions within return true.

=head3 or

Or blocks can contain a condition string, a condition block, or an array of conditions strings/blocks.
They return true if at least one of the conditions within returns true.

=head3 xor

Xor blocks can contain a condition string, a condition block, or an array of conditions strings/blocks.
They return true if only one of the conditions within returns true.

=cut

1;