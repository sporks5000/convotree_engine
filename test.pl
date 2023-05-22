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

### Initialize a connection and then remove the test tables if they exist
my $dbHandler = ConvoTreeEngine::Mysql->getConnection;
ConvoTreeEngine::Mysql->destroyTables;
ConvoTreeEngine::Mysql->closeConnection;

### Make a new connection and then re-create the test tables
$dbHandler = ConvoTreeEngine::Mysql->getConnection;

#========================#
#== Element Validation ==#
#========================#

my $element = ConvoTreeEngine::Object::Element->create({
	type => 'raw',
	json => {
		html => 'Some text',
	},
});

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