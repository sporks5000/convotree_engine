package ConvoTreeEngine::ElementExamples;

use strict;
use warnings;

use JSON;

our %examples = (
	item     => {
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
				"5" => 'For the text blocks, if the second string is null, a third string can include the name of a variable. the value of that variable will be displayed'
			},
		},
	},
	note     => {
		note  => 'Arbitrary text that will not be displayed to the user',
		arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
	},
	raw      => {
		html   => 'A string that will be interpreted as HTML and displayed to the user',
		delay  => 1000,
		prompt => JSON::false,
		stop   => JSON::false,
		arbit  => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "delay" key is optional. It contains a value in milliseconds for how long to pause before processing additional elements',
				"3" => 'The "prompt" key is optional. It contains a boolean value indicating whether to prompt before continuing',
				"4" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			},
		},
	},
	enter    => {
		start => "A string of text to begin a block. Example: '<div class=\"thing\">'\nUntil an \"exit\" block with the same name (or a null name) is reached, content will be placed within this block",
		end   => "A string of text to end a block. Example: '</div>'",
		name  => "One or more space or hyphen-separated words with no special characters except underscores",
		arbit => 'Optional; arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
	},
	exit     => {
		name  => "One or more space or hyphen-separated words with no special characters except underscores",
		all   => 1,
		arbit => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "name" key may be undefined (null). If so, it will trigger the exit of any previous "Enter" block',
				"3" => 'The "all" key is optional. It must be a boolean value. If true, it will trigger the exist of ALL previous "Enter" blocks that we might be nested within',
			},
		},
	},
	if       => {
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
				"6" => 'These nested arrays will be processed in order until one of them returns true',
				"7" => 'If the first element within a nested array is null, it will be interpreted as returning true',
			},
		},
	},
	assess   => {
		cond  => [
			'var=0',
			'1',
		],
		arbit => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => '"assess" blocks are similar to "if" blocks, except that they will be assessed (In the order they were presented) only after a "stop" block has been reached',
				"3" => 'The "cond" key will be a single array containing either one or two strings',
				"4" => 'The first string will contain one or more sets of a variable name, an operator, and a value',
				"4.a" => 'Variable names may contain letters, numbers, underscores or periods',
				"4.b" => 'Operators may be one of the following: "=", "!=", ">", "<", ">=", "<="',
				"4.c" => 'The value must contain only letters, numbers, and underscores',
				"4.d" => 'If there are multiple sets within within the first string, they will be separated by and ("&") or or ("|") operators',
				"5" => 'The second string (if present) willcontain either a single positive integer (representing a single element ID) or an array of positive integers',
				"6" => 'If the first element within the array is null, it will be interpreted as returning true',
			},
		},
	},
	negate   => {
		assess_id => "2",
		arbit     => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "assess_id" will contain the ID of an "assess" block or an array with multiple IDs of assess blocks. This negate block will remove the specified assess block from the assess queue',
			},
		},
	},
	stop     => {
		arbit => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'Remove all further elements from the queue to be processed; Begin processing elements in the "assess" queue.',
			},
		},
	},
	variable => {
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
	},
	choice   => {
		choices => [
			[
				undef,
				'display text',
				'1',
			],
			[
				'var=1',
				'display text',
				[1,2],
			],
		],
		arbit  => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "choices" key will contain an array of arrays',
				"3" => 'Each nested array within the "choices" key will contain either two or three strings',
				"4" => 'Instead of having a value, the first string can be null. this indicates that the display text for the option is not conditional and will always be present',
				"5" => 'The first string, if not null, will contain one or more sets of a variable name, an operator, and a value',
				"5.a" => 'Variable names may contain letters, numbers, underscores or periods',
				"5.b" => 'Operators may be one of the following: "=", "!=", ">", "<", ">=", "<="',
				"5.c" => 'The value must contain only letters, numbers, and underscores',
				"5.d" => 'If there are multiple sets within within the first string, they will be separated by and ("&") or or ("|") operators',
				"6" => 'The second string will contain the text to display to the user for that choice',
				"7" => 'The third string (if present) will contain either a single positive integer (representing a single element ID) or an array of positive integers',
				"8" => 'These nested arrays will be displayed to the user in the order given',
			},
		},
	},
	display  => {
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
				"3" => 'The "stop" key is optional. It contain a boolean value indicating whether or not the flow of elements sshould stop after this point (identical to a "stop" block)',
			},
		},
	},
	do       => {
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
	},
	data     => {
		get   => [1,2],
		arbit => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "get" key must contain either a single positive integer (representing a single element ID) or an array of positive integers',
			},
		},
	},
	series => {
		series => [1,2,3,5],
		arbit  => {
			"Additional details" => {
				"1" => 'The "arbit" key is optional. It may contain arbitrary data in the form of a JSON object, JSON array, or any other acceptable JSON data type',
				"2" => 'The "series" key must contain either a single positive integer (representing a single element ID) or an array of positive integers',
			},
		},
	},
);

1;