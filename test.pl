#!/usr/bin/perl

BEGIN {
	push @INC, "$ENV{HOME}/perl5/lib/perl5", "$ENV{HOME}/convotree_engine/modules";

	require ConvoTreeEngine::Config;
	my $normal = $ConvoTreeEngine::Config::tablePrefix;
	my $test   = $ConvoTreeEngine::Config::testTablePrefix;

	$ConvoTreeEngine::Config::tablePrefix = $test eq $normal ? "${normal}test_" : $test;
};

use strict;
use warnings;

use Data::Dumper;

use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Mysql;
use ConvoTreeEngine::Validation;
use ConvoTreeEngine::Object::Element;
use ConvoTreeEngine::Object::Element::Nested;
use ConvoTreeEngine::Object::StateData;

### Initialize a connection and then remove the test tables if they exist
my $dbHandler = ConvoTreeEngine::Mysql->getConnection;
ConvoTreeEngine::Mysql->destroyTables;
ConvoTreeEngine::Mysql->closeConnection;

### Make a new connection and then re-create the test tables
$dbHandler = ConvoTreeEngine::Mysql->getConnection;

#========================#
#== Element Validation ==#
#========================#

### Start by making three generic elements
my $element;
for (1 .. 3) {
	$element = ConvoTreeEngine::Object::Element->create({
		type => 'raw',
		json => {
			html => 'Some text',
		},
	});
}

my $prefix = $ConvoTreeEngine::Config::tablePrefix;
my $rows = ConvoTreeEngine::Mysql->fetchRows(qq/SELECT * FROM ${prefix}c_element_types/);
foreach my $row (sort {$a->{type} cmp $b->{type}} @$rows) {
	eval {
		### Turn off item type validation
		local $ConvoTreeEngine::Validation::STRICT_ITEM_TYPE_VALIDATION = 0;
		ConvoTreeEngine::Object::Element->create({
			type     => $row->{type},
			json     => $row->{example},
			name     => 'test ' . $row->{type},
			category => 'type tests',
		});
	};
	if (my $ex = $@) {
		ConvoTreeEngine::Exception::Unexpected->promote($ex);
		print STDERR "Type: $row->{type}\n";
		$ex->rethrow;
	}
}

$element->delete;

my $ne_table = ConvoTreeEngine::Object::Element::Nested->_table;

$rows = ConvoTreeEngine::Mysql->fetchRows(qq/SELECT DISTINCT(element_id) FROM $ne_table;/);
my @ids;
foreach my $row (@$rows) {
	push @ids, $row->{element_id};
}

my $elements = ConvoTreeEngine::Object::Element->searchWithNested(@ids);
print Data::Dumper::Dumper($elements);

### Verify that an arrayref instead of an array works
$elements = ConvoTreeEngine::Object::Element->searchWithNested(\@ids);
### Verify that a namecat works
$elements = ConvoTreeEngine::Object::Element->searchWithNested('type tests:test series');

##### TODO: Need to test update functionality here

my $validator = ConvoTreeEngine::Validation->new;
### Note: Not testing if these would be true, just if they pass validation
my @condition_string_tests = (
	'var=1',
	'var = 1',
	'var= 1',
	'var =1',
	'!var = 1',
	'taco=1&burrito=1',
	'taco=1|burrito=1',
	'taco = 1 | burrito=1',
	'taco=1 & burrito=1',
	'var=1&var=2|var=3',
	'var ==1',
	'var>1',
	'var<1',
	'var<=1',
	'var>=1',
	'var!== 1',
	'taco=1|!burrito=1',
	'taco="tingly tim"',
	"var = 'Pasta time!'",
	q/var ="It'sa me, Mario!"/,
	' var = 1 ',
	'seen:13',
	'!seen:13',
	'seen:taco:burrito',
	'seen : taco:burrito',
);

foreach my $cs (@condition_string_tests) {
	$validator->validateValue($cs, 'conditionString') || die "q/$cs/ did not pass as a condition string";
}

### Test that these fail validation
@condition_string_tests = (
	'var==taco',
	'var!==taco',
	'var>=taco',
	'var<=taco',
	'var>taco',
	'var<taco',
	'var=1 && var=2',
	'var',
	'var=1 || var=2',
	'var=1|var|var=2',
	'seen : taco:burrito:taco',
	'var=my face',
);

foreach my $cs (@condition_string_tests) {
	$validator->validateValue($cs, 'conditionString') && die "q/$cs/ did pass as a condition string (and should not have)";
}