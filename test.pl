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

use ConvoTreeEngine::Exceptions;
use ConvoTreeEngine::Mysql;
use ConvoTreeEngine::Object::Element;
use ConvoTreeEngine::Object::Series;

### Initialize a connection and then remove the test tables if they exist
my $dbHandler = ConvoTreeEngine::Mysql->getConnection;
ConvoTreeEngine::Mysql->destroyTables;
ConvoTreeEngine::Mysql->closeConnection;

### Make a new connection and then re-create the test tables
$dbHandler = ConvoTreeEngine::Mysql->getConnection;

#========================#
#== Element Validation ==#
#========================#

ConvoTreeEngine::Object::Element->create({
	type => 'raw',
	json => {
		html => 'Some text',
	},
});
ConvoTreeEngine::Object::Series->create({
	name     => 'series test 1',
	category => 'series test',
	sequence => [1],
});

my $prefix = $ConvoTreeEngine::Config::tablePrefix;
my $rows = ConvoTreeEngine::Mysql->fetchRows(qq/SELECT * FROM ${prefix}c_element_types/);
foreach my $row (@$rows) {
	eval {
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