package ConvoTreeEngine::ElementExamples;

use strict;
use warnings;

use JSON;

#======================#
#== Element Examples ==#
#======================#

our %examples;

=head2 Item

"Item" elements represent a story element, generally consisting of one or more paragraphs that will be
displayed to the user.

=cut

$examples{item} = {
	text     => {
		speaker => 'html classes',
		text    => 'A string of text potentially including "quoted bits", _underscored bits_, *starred bits*, and [bracketed bits].',
		classes => 'html classes',
		hover   => 'A string of text potentially including [bracketed bits].',
		frame   => 'html classes',
	},
	textx    => {
		speaker => 'html classes',
		text    => [
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
		classes => 'html classes',
		hover   => 'A string of text potentially including [bracketed bits].',
		frame   => 'html classes',
	},
	function => 'functionName',
	delay    => 500,
	prompt   => JSON::false,
	arbit    => {
		"Additional details" => {
			"01" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"02" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause after this element before processing additional elements. Default: 500 ms',
			"03" => 'The "prompt" key is optional and defaults to true. It can contain one of the following:',
			"03.a" => 'true, indicating that the user will be prompted with the default prompt before continuing',
			"03.b" => 'false, indicating that we will move straight to the next element',
			"03.c" => 'anything that the "text" key can be given (described below)',
			"04" => 'The "text" key can be given a string, or a hashref. If given a hashref and the "text" key within it is a string...',
			"04.a" => 'Quoted bits will be put into a span and given the classes specified under "speaker"',
			"04.a.1" => 'This will only apply to double quotes, not single quotes, smart quotes, or any other variety of quotes.',
			"04.b" => 'Underscored bits will be italicized',
			"04.c" => 'Starred bits will be bolded',
			"04.d" => 'Text within bracketed bits will be interpreted as a variable name, and replaced with the value of that variable',
			"04.e" => 'Newline characters will be replaced with html line breaks',
			"04.f" => 'Quotation marks, underscores, asterisks, square brackets, and backslashes preceeded by a backslash ("\") will be output as normal and not parsed.',
			"05" => 'If the "text" was given a hashref and the "text" key within that hashref is an arrayref...',
			"05.a" => 'It will contain any number of array refs',
			"05.b" => 'The first element in these will be a string of html classes to apply to the span (or null if none are to apply)',
			"05.c" => 'The second element will either be a string of text, or another arrayref of arrayrefs, nested as deeply as the creator needs',
			"05.c.1" => 'If the second element is a string of text, it will not be parsed in any way, except to sanitize characters that might be interpreted as HTML...',
			"05.c.2" => '...and to replace newline characters with html line breaks.',
			"05.d" => 'If the second string is null, a third string can include the name of a variable. the value of that variable will be displayed',
			"06" => 'If the "text" key was given a string, it will be parsed as if it was given a hashref with just the key "text" and that string (as described above)',
			"07" => 'The "hover" key in the "text" hashref will be text that is visible on mouseover',
			"08" => 'The "classes" key in the "text" hashref will be the html classes applied to the block as a whole',
			"09" => '"function" is the name of a function (if any) that will be run to generate how this element is displayed.',
			"10" => 'The "textx" key will have the same input as the "text" key. It represents what will be displayed in the Item block is not active',
			"10.a" => '...for example, if it is a choice where the conditions were not met',
		},
	},
};

=head2 Note

"Note" elements include additional details that will not be displayed to the user. They exist purely for
organizatioal purposes for the creator.

=cut

$examples{note} = {
	note  => 'Arbitrary text that will not be displayed to the user',
	arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
};

=head2 Raw

"Raw" elements are blocks that will be interpreted as HTML

=cut

$examples{raw} = {
	html   => 'A string that will be interpreted as HTML and displayed to the user',
	delay  => 500,
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

"Enter" and "exit" elements allow us to display items (or other story elements) within nested blocks.

=cut

$examples{enter} = {
	start => "A string of text to begin a block. Example: '<div class=\"thing\">'\nUntil an \"exit\" block with the same name (or a null name) is reached, content will be placed within this block",
	end   => "A string of text to end a block. Example: '</div>'",
	name  => "One or more space separated words with no special characters except underscores",
	arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
};
$examples{exit} = {
	name  => "One or more space separated words with no special characters except underscores",
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

"If" elements represent a place where the story is able to fork in different directions based on various conditions

=cut

$examples{if} = {
	cond  => [
		[
			'var=0',
			[1,2],
			'optional text (not displayed to the user)',
		],
	],
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "cond" key will contain an array of arrays',
			"3" => 'Each nested array within the "cond" key will contain either one or two items',
			"3.a" => 'The first item will be either a condition string, a condition block, an array of condition strings, or undef/null',
			"3.b" => 'The second item (if present) will either be a single element identifier, or an arrayref of element identifiers',
			"3.c" => 'If a third item is present, it willbe arbitrary text that is not displayed to the user',
			"4" => 'The conditions within these nested array will be processed in the order given.',
			"4.a" => 'The first condition to return true will determine that path the narrative takes.',
			"4.b" => 'further conditions beyond the first the passed as true will be ignored.',
		},
	},
};

=head2 Stop

"Stop" elements indicate that no further queued elements after this point should be displayed. They
are cleared from the queue.

=cut

$examples{stop} = {
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'Remove all further elements from the queue to be processed',
		},
	},
};

=head2 Variable

"Variable" elements set or update the value of a variable.

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
			"2.a" => 'Variable names can contain uppercase and lowercase letters, numbers, underscores, and periods',
			"3" => 'If the value begins with "+=", "-=", "*=", or "/=", followed by a number it is assumed that we will be adding to, subtracting from, multiplying by, or dividing from that value',
			"3.a" => 'If there is no existing value, we assume the value of 0',
			"3.b" => 'If there is an existing value, but does not appear to be a number, we simply replace that value with the string given',
		},
	},
};

=head2 Choice

"Choice" elements represent an instance where the user has the ability to make a choice in the narrative.
There is the potential for choices to be unavialable based on the values of various variables.

=cut

$examples{choice} = {
	choices => [
		{
			cond          => undef,
			element       => 2,
			then          => 2,
			disp_inactive => JSON::false,
			classes       => 'even more classes',
			arbit         => 'EVEN MORE arbitrary data',
		},
	],
	delay   => 500,
	classes => 'html classes',
	keep    => 1,
	arbit   => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It indicates how long to wait before displaying the choices',
			"3" => 'The "choices" key will contain an array of hashes, containing the following keys',
			"3.a" => '"cond" is the conditions necessary for the option to be available. undef indicates that it is always available. If the key is not present, it is always available',
			"3.b" => '"element" is the ID or namecat of the element to display for this choice',
			"3.c" => '"then" is the element or an array of elements that will follow if this option is chosen',
			"3.d" => '"disp_inactive" is a boolean value indicating whether or not to display the choics if it is not active. Default: false',
			"3.e" => '"arbit" is a place to store more optional arbitrary data. Can be useful for holding information if the condition calls a function',
			"4" => 'These choices will be displayed to the user in the order given',
			"5" => 'The "keep" key can be the numbers "0, 1, or 2. 1 is assumed by default',
			"5.a" => 'If "keep" is set to "0", all choices will be removed from the display after one is selected.',
			"5.b" => 'If "keep" is set to "1", all choices but the one that was selected will be removed from the display after one is selected.',
			"5.c" => 'If "keep" is set to "2", all choices will remain displayed after one is selected.',
		},
	},
};

=head2 Display

"Display" elements will update the CSS of the page.

##### TODO: Do these replace existing CSS or add to existing CSS?

=cut

$examples{display} = {
	mine      => {
		'css selector' => 'text-align: left; background-color: #000000;',
	},
	all       => {
		'css selector' => 'text-align: left; background-color: #000000;',
	},
	wipe_mine => JSON::false,
	wipe_all  => JSON::false,
	delay     => 500,
	arbit     => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "mine" key is a hashref of css selectors to the CSS that will apply to them, and only within the convoTreeEngine div',
			"4" => 'The "all" key is a hashref of css selectors to the CSS that will apply to them, regardless of where they are present in the page',
			"5" => 'The "wipe_mine" and "wipe_all" keys, if present and true, indicate that all of the styles currently set should be removed before adding new ones',
		},
	},
};

=head2 Do

"Do" elements indicate that the specified javascript function should be run.

=cut

$examples{do} = {
	function => 'functionName',
	args     => [
		'arg1',
		'arg2',
	],
	delay    => 500,
	stop     => JSON::false,
	arbit    => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
			"3" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			"4" => 'The function name must be a string of letters, numbers, and underscores',
			"5" => 'The "args" key is optional; It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
		},
	},
};

=head2 Elements's

"Elements" elements specify actions to take regarading elements themselves. They can indicate to
get more elements from the server, or to queue more elements up to be processed next (or both).

=cut

$examples{elements} = {
	get   => [1, 2, 3],
	queue => [1, 2],
	drop  => JSON::false,
	jump  => '1',
	arbit => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'Both the "get" and "queue" keys muust have a value that is a single element identifier (ID or namecat) or an arrayref of element identifiers',
			"3" => 'Elements specified under the "get" key will be requested from the server (if they have not been already)',
			"4" => 'Elements specified under the "queue" key will be added to the queue of elements to process next',
			"5" => 'If the "drop" key is true, drop all existing items from the queue',
			"6" => 'If the "jump" key is present, move forward in the queue until the element specified is the next element (or until the end of the queue is reached)',
			"6.a" => 'If an array of elements is given instead of a single one, move forward until ANY of them are the next one',
		},
	},
};

=head2 Random

"Ramdom" elements indicate an instance where the path of the story can fork at random.

=cut

$examples{random} = {
	paths    => [
		[
			5,
			1,
		],
		[
			3,
			[1, 4],
		],
	],
	function => 'functionName',
	arbit    => {
		"Additional details" => {
			"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
			"2" => 'The "paths" key must contain an array fo arrays. Each of the nested arrays will contain towo elements, a number, and an element id, or arrayref of element ids',
			"2.a" => 'The first number will indicate the weight of the potential for that event occurring. Higher means it is more likely.',
			"3" => 'If a function name is given, the data for this element will be passed into that function, and the returned value will be interpreted as if it is the data for the element',
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

* =   - Indicates number or string equivalence
* !=  - Indicates number or string inequivolence
* >=  - Indicates that the number is greater than or equal to
* <=  - Indicates that the number is lesser than or equal to
* >   - Indicates that the number is greater than
* <   - Indicates that the number is lesser than
* ==  - Indicates numerical equivalence
* !== - Indicates numerical inequivolence

...with the numerical-only operators holding to a strict rule of: If either the value of the variable
or the value it's being compared to do not look like a number, the condition will return false.

If the string as a whole is preceeded by an exclamation point, return true if the condition would
otherwise return false.

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

* not
* and
* or
* xor

All of these keys can have a value that is either null/undef, a condition string, a condition block,
or an array where each element is either null/undef, a condition string, or a condition block.

If a condition block contains more than one of the above keys, it only returns true if ALL of them
return true.

=head3 not

Returns true if the conditions presented did NOT return true.

=head3 and

Returns true if all of the conditions presented are true.

=head3 or

Returns true if at least one of the conditions presented is true.

=head3 xor

Returns true if ONLY one of the conditions presented returned true.

=cut

1;