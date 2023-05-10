package ConvoTreeEngine::Object;

use strict;
use warnings;

use Data::Dumper;

use ConvoTreeEngine::Utils;
use ConvoTreeEngine::Config;
use ConvoTreeEngine::Mysql;
use ConvoTreeEngine::Exceptions;

sub _table {
	my $self  = shift;
	my $table = shift;
	return $ConvoTreeEngine::Config::tablePrefix . $table;
}

sub _prep_args {
	my $self = shift;

	return {} unless @_;

	return $_[0] if (ref($_[0]) || '') eq 'HASH';

	ConvoTreeEngine::Exception::Internal->throw(
		error => "odd number of parameters cannot be cast as hash",
	) if @_ % 2;

	for (my $i = 0; $i < @_; $i += 2) {
		ConvoTreeEngine::Exception::Internal->throw(
			error => "has keys must be defined",
		) unless defined $_[$i];
	}

	return {@_};
}

sub _prep_args_multi {
	my $self  = shift;
	my $count = shift;

	return {} unless @_;

	my @response;
	while (@_ && (ref($_[0]) || '') eq 'HASH') {
		push @response, shift;
	}

	if (@_) {
		push @response, $self->_prep_args(@_);
	}

	while (@response < $count) {
		push @response, {};
	}

	return @response;
}

{
	my %describes;
	my %primary_keys;
	sub _field_details {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $describes{$table} ||= do {
			my $fieldDetails = { map {$_->{Field} => $_} @{ $invocant->_mysql->fetchRows(qq/DESCRIBE $table;/) } };

			my @primary;
			foreach my $field (sort keys %$fieldDetails) {
				if (($fieldDetails->{$field}{Key} || '') eq 'PRI') {
					push @primary, $field;
				}
			}
			if (@primary) {
				$primary_keys{$table} = \@primary;
			}

			$fieldDetails;
		};
	}

	sub _primary_keys {
		my $invocant = shift;

		my $table = $invocant->_table;
		return $primary_keys{$table} || do {
			$invocant->_field_details();
			$primary_keys{$table};
		};

	}
}

=head2 _baseClass and _dynamicSubclass

Given a scenario where a class needs to be subclassed, these two methods can
be subclassed in order to ensure that objects end up in the appropriate subclass.

The '_baseClass' method should return the name of the lowest class from which
code specific to that table is inherited.

The '_dynamicSubclass' method expects to be passed the data from which we're
going to create the object. It will assess that data and return an appropriate
subclass.

=cut

sub _baseClass {}
sub _dynamicSubclass {}

=head2 __dynamicSubclass

Given data that is to be blessed into an object, Check the class that it's to be
blessed into to see if it should be subclassed. Continue to check the returned
subclasses for further subclassing until either the same class is returned or
nothing is returned.

=cut

sub __dynamicSubclass {
	my $invocant = shift;
	my $data     = shift;

	my $class = Scalar::Util::blessed($invocant) || $invocant;

	$class = $class->_baseClass || $class;
	my $newClass = '';
	while ($newClass ne $class) {
		ConvoTreeEngine::Utils->require($class);
		$newClass = $class;
		$class = $class->_dynamicSubclass($data) || $class;
	}

	return $class;
}

=head2 createAccessors

Given a list of field names, assume that the class represents a hashref object where each
field name is a key on that object and create a method for each field name where the value
of that key is returned.

Because objects from this class are DB-backed, we want to route all updates through the
'update' method, so only create accessors as read only.

=cut

sub createAccessors {
	return ConvoTreeEngine::Utils->createROAccessors(@_);
}

=head2 createRelationships

Creaete a relationship between the calling class and another class

Expects an array of hashrefs with the following keys:

* name     - The name of the method
* class    - The other class that we're relating to
* fields   - A hashref where the keys are the names of args that would be passed into the other
             method's 'search' class and each value is either 1) a method on the calling class
             which will be called to determine the value, or 2) a code ref (expecting the
             calling object to be passed in as the only argument) which will be called to return
             a value, or 3) a scalar-ref of the specific value or a ref-ref of the specific
             arrayref or hashref to use. Alternately, instead of a hashref, if only comparing a
             single field, and the name is the same on both ends, you can just use that name.
* order_by - Optional; a default order to use if no others are specified
* many     - Optional, boolean; If present and true, call 'search', otherwise call 'find'
* join     - See below.

The above can be fairly straightforward for one-to-one and one-to-many relationships, however
with many-to-many relationshipsthis becomes more complex. The code here has a solution for
many-to-many relationships that are achieved with a separate table containing two columns, each
contaninig references to the two related tables. With this, the keys in the 'fields' hashref are
looking at either of the other tables, and 'join' will either contain 1) an arrayref with the
intermediary class name, the field on the destination class, and the related field on the
intermediary class, or 2) a coderef that will produce the join string, or 3) a scalar containing
a JOIN string.

Example 1:

    SELECT * FROM cp_license
    JOIN pull_to_license ON cp_license.id = pull_to_license.license_id
    WHERE pull_to_license.pull_id = ?;

    ... where '?' is the value of the 'id' column on a row of the "pull" table

Solution A:

{
    class  => 'ACW::Objects::SQLite::LicenseReconcile::CPLicense',
    fields => {ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table . '.pull_id' => 'id'},
    join   => ['ACW::Objects::SQLite::LicenseReconcile::PullToLicense', 'id', 'license_id'],
    many   => 1,
}

Solution B:

{
    class  => 'ACW::Objects::SQLite::LicenseReconcile::CPLicense',
    fields => {ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table . '.pull_id' => 'id'},
    join   => 'JOIN pull_to_license ON cp_license.id = pull_to_license.license_id',
    many   => 1,
}

Solution C:

{
    class  => 'ACW::Objects::SQLite::LicenseReconcile::CPLicense',
    fields => {ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table . '.pull_id' => 'id'},
    join   => sub {
        my $self = shift; ### Not doing anything with it in this example, but we could.
        my $destTable = ACW::Objects::SQLite::LicenseReconcile::CPLicense->_table;
        my $joinTable = ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table;
        return "JOIN $joinTable ON $destTable.id = $joinTable.license_id";
    },
    many   => 1,
}

Example 2:

    SELECT * FROM pull
    JOIN pull_to_license ON pull.id = pull_to_license.pull_id
    WHERE pull_to_license.license_id = ? AND pull.type = 'cpanel';

    ... where '?' is the value of the 'id' column on a row of the "cp_license" table

Solution A:

{
    class  => 'ACW::Objects::SQLite::LicenseReconcile::Pull',
    fields => {ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table . '.license_id' => 'id', type => \'cpanel'},
    join   => ['ACW::Objects::SQLite::LicenseReconcile::PullToLicense', 'id', 'pull_id'],
    many   => 1,
}

Solution B:

{
    class  => 'ACW::Objects::SQLite::LicenseReconcile::Pull',
    fields => {ACW::Objects::SQLite::LicenseReconcile::PullToLicense->_table . '.license_id' => 'id', type => \'cpanel'},
    join   => 'JOIN pull_to_license ON pull.id = pull_to_license.pull_id',
    many   => 1,
}

Really, if you're trying to achieve anything more complicated than this would allow, then what
you're trying to do would probably be more confusing to do this way than it would to just create
your own method within the class and give it proper commenting and such.

=cut

sub createRelationships {
	my $class         = shift;
	my @relationships = @_;

	my $getValue; $getValue = sub {
		my $self       = shift;
		my $selfMethod = shift;

		my $value;
		my $ref = ref $selfMethod || '';
		if ($ref eq 'CODE') {
			$value = $selfMethod->($self);
		}
		elsif ($ref eq 'ARRAY') {
			$value = [];
			foreach my $nested (@$selfMethod) {
				push @$value, $getValue->($self, $nested);
			}
		}
		elsif ($ref eq 'HASH') {
			$value = {};
			foreach my $key (keys %$selfMethod) {
				$value->{$key} = $getValue->($self, $selfMethod->{$key});
			}
		}
		elsif ($ref eq 'SCALAR' || $ref eq 'REF') {
			$value = $$selfMethod;
		}
		else {
			$value = $self->$selfMethod();
		}

		return $value;
	};

	foreach my $rel (@relationships) {
		my $symbol_name = "${class}::$rel->{name}";
		no strict 'refs';
		next if defined *{$symbol_name};
		my $otherClass = $rel->{class};
		ConvoTreeEngine::Utils->require($otherClass);

		$rel->{fields} = {$rel->{fields} => $rel->{fields}} unless ref $rel->{fields};
		if ($rel->{order_by}) {
			$rel->{order_by} = ConvoTreeEngine::Utils->convert_to_array($rel->{order_by});
		}

		if ($rel->{join}) {
			my $ref = ref $rel->{join} || '';
			if ($ref eq 'ARRAY' && @{$rel->{join}} == 3) {
				my $joinClass = $rel->{join}[0];
				ConvoTreeEngine::Utils->require($joinClass);

				my $joinTable  = $joinClass->_table;
				my $destTable  = $otherClass->_table;
				my $destColumn = $rel->{join}[1];
				my $joinColumn = $rel->{join}[2];

				$rel->{join} = "JOIN $joinTable ON $destTable.$destColumn = $joinTable.$joinColumn";
			}
			elsif ($ref = 'CODE') {
				### Do nothing
			}
			elsif ($ref) {
				die "Improper formatting for relationship 'join' field: " . Data::Dumper::Dumper($rel->{join});
			}
		}

		my $mutate = '__' . $rel->{name} . '_mutateArgs';
		*{"${class}::$mutate"} = sub {
			my $self = shift;
			my $args = shift;

			### We're going to mutate args, so do a shallow clone of them
			$args = {map {$_ => $args->{$_}} keys %$args};

			my $args2 = {};;
			foreach my $otherField (keys %{$rel->{fields}}) {
				my $selfMethod = $rel->{fields}{$otherField};
				my $value = $getValue->($self, $selfMethod);
				if ($otherField eq 'DISTINCT') {
					$args->{DISTINCT} = $value;
				}
				else {
					$args2->{$otherField} = $value;
				}
			}

			my $fieldDetails = $otherClass->_field_details;

			my $whereString;
			my @whereString;
			if ($args->{WHERE}) {
				$args->{WHERE} = ConvoTreeEngine::Utils->convert_to_array($args->{WHERE});
				foreach my $where (@{$args->{WHERE}}) {
					push @whereString, $where;
				}
			}
			my @input;
			push @input, @{$args->{INPUT}} if $args->{INPUT};

			$otherClass->_parse_where_args(\@whereString, \@input, $fieldDetails, $args2);

			$whereString = join ' AND ', @whereString;
			$args->{WHERE} = $whereString;
			$args->{INPUT} = \@input;

			if (my $join = $rel->{join}) {
				if (ref $join) {
					$join = $join->($self);
				}
				$args->{JOIN} = $args->{JOIN} ? $args->{JOIN} . ' ' . $join : $join;
			}

			return $args;
		};
		if ($rel->{many}) {
			*{$symbol_name} = sub {
				my $self = shift;
				my ($args, $attrs) = $class->_prep_args_multi(2, @_);

				$args = $self->$mutate($args);
				if ($rel->{order_by}) {
					### We're going to mutate attrs, so do a shallow clone of them
					$attrs = {map {$_ => $attrs->{$_}} keys %$attrs};

					$attrs->{order_by} = ConvoTreeEngine::Utils->convert_to_array($attrs->{order_by}, $rel->{order_by});
				}

				return $otherClass->search($args, $attrs);
			};
		}
		else {
			*{$symbol_name} = sub {
				my $self = shift;
				my $args = $class->_prep_args(@_);

				$args = $self->$mutate($args);

				return $otherClass->find($args);
			};
		}
	}

	return;
}

sub create {
	my $class = shift;
	my $args  = $class->_prep_args(@_);

	my $objData = {};

	my $fieldDetails = $class->_field_details;

	my $table = $class->_table;
	my (@fields, @values);
	foreach my $field (sort keys %$fieldDetails) {
		if (exists $args->{$field}) {
			push @fields, $field;
			if ($args->{$field} && ref $args->{$field} && $fieldDetails->{$field}{Type} eq 'json') {
				$args->{$field} = JSON::encode_json($args->{$field});
			}
			push @values, $args->{$field};
			$objData->{$field} = delete $args->{$field};
		}
	}
	if (keys %$args) {
		ConvoTreeEngine::Exception::Input->throw(
			error => "Table '$table' does not have column(s) [" . join(', ', sort(keys %$args)) . ']',
		);
	}

	my $questionmarks = join ',', ('?') x @fields;
	my $fields = join ',', @fields;

	if ($fieldDetails->{id} && ($fieldDetails->{id}{Key} || '') eq 'PRI') {
		my $id = $class->_mysql->insertForId(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);
		$objData->{id} = $id;
	}
	else {
		$class->_mysql->doQuery(qq/INSERT INTO $table($fields) VALUES($questionmarks);/, [@values]);
	}

	return $class->promote($objData);
}

sub _parse_query_attrs {
	my $invocant     = shift;
	my $attrs        = shift;
	my $fieldDetails = shift || $invocant->_field_details;

	my $table = $invocant->_table;

	my @string;

	### We're going to mutate args, so do a shallow clone of them
	$attrs = {map {$_ => $attrs->{$_}} keys %$attrs};

	if (defined $attrs->{order_by}) {
		$attrs->{order_by} = ConvoTreeEngine::Utils->convert_to_array($attrs->{order_by});
		my @order;
		foreach my $order (@{$attrs->{order_by}}) {
			if ((ref $order || '') eq 'SCALAR') {
				push @order, $$order;
				next;
			}
			my @fields = split m/\s*,\s*/, $order;
			foreach my $f (@fields) {
				my ($field, $direction) = split m/\s+/, $f, 2;
				if ($field =~ m/^me\.[^.]+$/) {
					$field = "$table." . substr($field, 3);
				}
				elsif ($fieldDetails->{$field} && $field !~ m/\./) {
					$field = "$table.$field";
				}
				$field = "$field " . uc($direction) if $direction;
				push @order, $field;
			}
		}

		my $string = join ', ', @order;
		push @string, "ORDER BY $string";
	}
	if (defined $attrs->{limit}) {
		push @string, 'LIMIT ' . $attrs->{limit};
	}
	if (defined $attrs->{offset}) {
		push @string, 'OFFSET ' . $attrs->{offset};
	}

	return join(' ', @string) || '';
}

sub _parse_where_args {
	my $invocant     = shift;
	my $whereString  = shift;
	my $input        = shift;
	my $fieldDetails = shift;
	my $args         = shift;

	my $ref = ref($args) || '';

	if ($ref eq 'ARRAY') {
		foreach my $argPart (@$args) {
			my @nestedWhereString;
			$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, $argPart);
			next unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				my $string = '(' . join(' AND ', @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		return;
	}
	return unless $ref eq 'HASH';

	### We're going to mutate args, so do a shallow clone of them
	$args = {map {$_ => $args->{$_}} keys %$args};
	delete @{$args}{qw/WHERE JOIN INPUT DISTINCT/};

	my $table = $invocant->_table;
	foreach my $field (keys %$args) {
		next if $field =~ m/^-?(AND|OR)$/i;
		if ($field =~ m/^me\.[^.]+$/) {
			$args->{"$table." . substr($field, 3)} = delete $args->{$field};
		}
		elsif ($fieldDetails->{$field} && $field !~ m/\./) {
			$args->{"$table.$field"} = delete $args->{$field};
		}
	}

	FIELD:
	foreach my $field (keys %$args) {
		my $ref = ref($args->{$field}) || '';
		if ($field =~ m/^-?(AND|OR)$/i) {
			my @nestedWhereString;
			$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, $args->{$field});
			next FIELD unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				$field =~ s/^-//;
				$field = uc($field);
				my $string = '(' . join(" $field ", @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		elsif ($ref eq 'ARRAY') {
			my $string = "$field IN (";
			my $hasUndef = 0;
			my $count = 0;
			my @complex;
			foreach my $value (@{$args->{$field}}) {
				if (!defined $value) {
					$hasUndef = 1;
				}
				elsif (ref $value) {
					push @complex, $value;
				}
				else {
					$count++;
					push @$input, $value;
				}
			}

			my @nestedWhereString;
			if ($hasUndef) {
				push @nestedWhereString, "$field IS NULL";
			}
			if ($count) {
				if ($count == 1) {
					push @nestedWhereString, "$field = ?";
				}
				else {
					my $string= "$field IN (" . join(',', ('?') x $count) . ')';
					push @nestedWhereString, $string;
				}
			}
			if (@complex) {
				foreach my $value (@complex) {
					$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, {$field => $value});
				}
			}

			next FIELD unless @nestedWhereString;
			if (@nestedWhereString == 1) {
				push @$whereString, $nestedWhereString[0];
			}
			else {
				my $string = '(' . join(" OR ", @nestedWhereString) . ')';
				push @$whereString, $string;
			}
		}
		elsif ($ref eq 'HASH') {
			HASH_KEY:
			foreach my $key (keys %{$args->{$field}}) {
				### Allowing multiple keys is useful if we want to search for greater than one value and less than another
				my $value = $args->{$field}{$key};
				my $ref = ref $value || '';
				if (!defined $value) {
					$key = 'IS' if $key eq '=';
					$key = 'IS NOT' if $key eq '!=';
					push @$whereString, "$field $key NULL";
				}
				elsif ($ref eq 'ARRAY') {
					if ($key =~ m/^-?(AND|OR)$/i) {
						my @nestedWhereString;
						foreach my $val (@$value) {
							$invocant->_parse_where_args(\@nestedWhereString, $input, $fieldDetails, {$field => $val});
						}
						next HASH_KEY unless @nestedWhereString;
						if (@nestedWhereString == 1) {
							push @$whereString, $nestedWhereString[0];
						}
						else {
							$key =~ s/^-//;
							$key = uc($key);
							my $string = '(' . join(" $key ", @nestedWhereString) . ')';
							push @$whereString, $string;
						}
					}
					else {
						### Useful for the 'LIKE' operator
						foreach my $val (@$value) {
							if (!defined $val) {
								$key = 'IS' if $key eq '=';
								$key = 'IS NOT' if $key eq '!=';
								push @$whereString, "$field $key NULL";
							}
							else {
								push @$whereString, "$field $key ?";
								push @$input, $val;
							}
						}
					}
				}
				elsif ($ref eq 'SCALAR') {
					push @$whereString, "$field $key $value";
				}
				else {
					push @$whereString, "$field $key ?";
					push @$input, $value;
				}
			}
		}
		elsif ($ref eq 'SCALAR') {
			push @$whereString, "$field ${$args->{$field}}";
		}
		else {
			if (defined $args->{$field}) {
				push @$whereString, "$field = ?";
				push @$input, $args->{$field};
			}
			else {
				push @$whereString, "$field IS NULL";
			}
		}
	}

	return;
}

=head2 _parseJoin

Parse the given join statement and make sure that we're not joining anything twice.

=cut

sub _parseJoin {
	my $invocant = shift;
	my $join     = shift;

	my $myTable = $invocant->_table;

	$join =~ s/\s+/ /g;
	my $joinOriginal = $join;
	my %joins;
	while ($join) {
		my ($type, $table, $alias, $clause);
		### Regex encased in curly brackets so that the $1, $2 etc. variables don't escape
		{
			$join =~ m/^\s*((((natural\s+)?((left|right|full)(\s+outer)?|inner)|cross)\s+)?join)/i;
			$type = $1;
		}

		unless ($type) {
			die "Unable to parse join statement:\n$join\n";
		}

		$join =~ s/^\s*$type\s//;
		my $keep = $join;
		{
			$keep =~ s/\s+(((natural\s)?((left|right|full)(\souter)?|inner)|cross)\s)?join\s.*$//i;
		}

		{
			$keep =~ m/^([A-Za-z0-9_]+)\s(([A-Za-z0-9_]+)\s)?((ON|USING)(\s|\().*)$/i;
			$table  = $1;
			$alias  = $3 || $table;
			$clause = $4;
		}

		unless ($table && $clause) {
			die "Unable to parse join statement:\n$type $keep\n";
		}

		if ($joins{$alias}) {
			die "Joined to table or alias '$alias' more than once in statement:\n$joinOriginal\n";
		}
		if ($alias eq $myTable) {
			die "Joined back to original table '$myTable' without an alias in statement:\n$joinOriginal\n";
		}
		$joins{$alias} = 1;

		$join =~ s/^\s*$keep\s*//;
	}

	return;
}

=head2 search

Compose a query string, Make the query, return the results.

Expects two arguments, $args and $attrs. See `_parse_query_attrs` for explanation of attrs

=head3 $args

$args can contain the following special arguments:

* WHERE    - A text string (or an array of text strings) containing a SQL "WHERE" clause (not
             begining with the word "WHERE", but everything that comes after that). This will
             be prepended with an "AND" to any where string that's generated from the other
             passed-in arguments.
* JOIN     - A text string containing one or more SQL "JOIN" clauses (beginning with the
             appropriate "JOIN", "LEFT JOIN", etc keywords).
* INPUT    - An arrayref of args that would be inserted into any passed-in WHERE statement.
* DISTINCT - Boolean; indicates that we're doing a 'SELECT DISTINCT' rather than just a 'SELECT'

The following patterns can be used:

* {field => $value}
    * Translates to the string "field = $value" (or "field IS NULL" if the value is undef)
    * The value will be appropriately quoted

* {field => [$value1, $value2, $value3]}
    * Translates to the string "field IN ($value1, $value2, $value3)"
    * If one of the values is undef, instead translates to "(field IS NULL OR field IN
      ($value1, $value3))"
    * The values will be appropriately quoted

* {field => [$value1, $value2, {$operator => $value3}]}
    * Example: {field => [1, 3, {'>' => 7}]}
    * The example would translate to the string "(field IN (1, 3) OR field > 7)"

* {field => {$operator => $value}}
    * Example: {count => {'>' => 1}}
    * The example would translate to the string "field > 1"
    * If the operator is "=" or "!=" and the value is undef, translates to "field IS NULL"
      or "filed IS NOT NULL"
    * The value will be appropriately quoted

* {$field => {$operator1 => $value1, $operator2 => $value2}}
    * Translates to something similar to "field $operator1 $value1 AND field $operator2 $value2"
    * Useful for generating a string like "field > 1 AND field < 3"
    * See above for other details

* {field => {$operator => [$value1, $value2]}}
    * Translates to a string similar to "field $operator $value1 AND field $operator $value2"
    * Useful for the "LIKE" operator
    * See above for other details

* {field => {$operator => \'value'}}
    * Assuming the operator was "=", this would translate to the string "field = value" without
      quotes around "value".
    * Useful for instances where you're comparing the contents of two columns
        * Example: {start_date => {'>' => \'end_date'}}
        * Becomes: 'start_date > end_date'

* {field => \$value}
    * Translates to the string "field $value"
    * Presumably $value contains an operator and a value. If so, that falue will need to have
      been appropriately quoted in the string

* {OR => {field1 => $value1, field2 => $value2}}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field1 = $value1 OR field2 = $value2)"

* {OR => [{field => $value1}, {field => $value2}]}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field = $value1 OR field = $value2)"

* {field => {OR => [$value1, $value2]}}
    * Both "AND" and "OR" are supported
    * Translates to the string "(field = $value1 OR field = $value2)"

* {field => {OR => [{$operator => $value1}, {$operator => $value2}]}}
    * Both "AND" and "OR" are supported
    * Example: {field => {OR => [{'>' => 1}, {'<' => 5}]}}
    * The example would translate to the string "(field > 1 OR field < 5)"

In any instance where "OR" or "AND" are used above, it is acceptable to use '-or' or '-and'
instead.

If the name of a field begins with the string 'me.', the 'me' will automatically be replaced
with the name of the table being searched against.

If the name of a field is the name of a column on the table, that field will automatically
be prerended with the table name. I.E. {field => 1} will become the string 'table.field = 1'.
Note that this does not apply to strings within scalar references.

=head3 $attrs

$attrs can contain any/all of three arguments:

* limit    - Specify a maximum number of results you wish to have returned.
* offset   - Skip returning the first X results.
* order_by - Specify the order in which results can be returned.

The 'order_by' argument must contain either a string of text or a scalarref, or an an array
of strings or scalarrefs. Each scalarref will be interpreted exactly as written. Each
string must contain a field name and optionally a direction. Optionally, it may contain
multiple fieldname/direction pairs, separated by commas. Directions must be "ASC" or "DESC".

Examples:

* {order_by => 'field1'}
    * Interpreted as 'ORDER BY table_name.field1'
* {order_by => 'other_table_name.field1'}
    * Interpreted as 'ORDER BY other_table_name.field1'
* {order_by => 'field1 DESC'}
    * Interpreted as 'ORDER BY table_name.field1 DESC'
* {order_by => 'field1, field2'}
    * Interpreted as 'ORDER BY table_name.field1, table_name.field2'
* {order_by => 'field1 ASC, field2 DESC'}
    * Interpreted as 'ORDER BY table_name.field1 ASC, table_name.field2 DESC'
* {order_by => 'field1, field2 DESC, field3 ASC'}
    * Interpreted as 'ORDER BY table_name.field1, table_name.field2 DESC, table_name.field3 ASC'
* {order_By => ['field1', 'field2 DESC']}
    * Interpreted as 'ORDER BY table_name.field1, table_name.field2 DESC'
* {order_By => ['field1', \'table_name.field2 + field3 DESC']}
    * Interpreted as 'ORDER BY table_name.field1, table_name.field2 + field3 DESC'

=cut

sub search {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $fieldDetails = $invocant->_field_details;
	my $attrString = $invocant->_parse_query_attrs($attrs, $fieldDetails);

	my $table = $invocant->_table;

	my $joinString = '';
	if ($args->{JOIN}) {
		$joinString = $args->{JOIN};
	}
	$invocant->_parseJoin($joinString) if $joinString;

	my $distinct = $args->{DISTINCT} ? ' DISTINCT' : '';

	my $whereString;
	my @whereString;
	if ($args->{WHERE}) {
		$args->{WHERE} = ConvoTreeEngine::Utils->convert_to_array($args->{WHERE});
		foreach my $where (@{$args->{WHERE}}) {
			push @whereString, $where;
		}
	}
	my @input;
	push @input, @{$args->{INPUT}} if $args->{INPUT};

	$invocant->_parse_where_args(\@whereString, \@input, $fieldDetails, $args);

	$whereString = join ' AND ', @whereString;
	$whereString = "WHERE $whereString" if $whereString;

	my $fields = "$table." . join(", $table.", keys(%$fieldDetails));
	my $query = qq/
		SELECT$distinct $fields FROM $table
		$joinString
		$whereString
		$attrString
	/;
	my $rows = $invocant->_mysql->fetchRows($query, \@input);

	foreach my $row (@$rows) {
		$invocant->promote($row);
	}

	return @$rows;
}

sub find {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);
	my @result = $invocant->search($args, $attrs);

	if (@result > 1) {
		ConvoTreeEngine::Exception::DuplicateRecord->throw(
			args => $args,
		);
	}

	return $result[0];
}

sub findOrDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	return $result if $result;
	ConvoTreeEngine::Exception::RecordNotFound->throw(
		args => $args,
	);
}

sub findAndDie {
	my $invocant = shift;
	my ($args, $attrs) = $invocant->_prep_args_multi(2, @_);

	my $result = $invocant->find($args, $attrs);
	ConvoTreeEngine::Exception::DuplicateRecord->throw(
		args => $args,
	) if $result;

	return;
}

sub _primary_key_where_clause {
	my $invocant = shift;

	my $table = $invocant->_table;
	my $primary_keys = $invocant->_primary_keys;
	die "Table '$table' does not have primary keys" unless $primary_keys && @$primary_keys;

	my @where;
	my @bits;
	foreach my $key (@$primary_keys) {
		push @where, "$key = ?";
		push @bits, $invocant->{$key};
	}
	my $where = join ' AND ', @where;

	return ($where, \@bits);
}

sub update {
	my $self = shift;
	my $args = $self->_prep_args(@_);

	my @ro = $self->_read_only_fields;
	foreach my $field (@ro) {
		if (exists $args->{$field}) {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$field' field cannot be updated on the '" . ref $self . "' object",
				args  => $args,
			) unless ConvoTreeEngine::Utils->compare($args->{$field}, $self->$field());
		}
	}

	my $fieldDetails = $self->_field_details;

	my @sets;
	my @bits;
	foreach my $arg (keys %$args) {
		if ($fieldDetails->{$arg}) {
			push @sets, "$arg = ?";
			if ($args->{$arg} && ref $args->{$arg} && $fieldDetails->{$arg}{Type} eq 'json') {
				$args->{$arg} = JSON::encode_json($args->{$arg});
			}
			push @bits, $args->{$arg};
		}
		else {
			ConvoTreeEngine::Exception::Input->throw(
				error => "The '$arg' field does not exist on the '" . ref $self . "' object",
				args  => $args,
			);
		}
	}
	my $sets = join ', ', @sets;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;
	push @bits, @$pk_bits;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/UPDATE $table SET $sets WHERE $where;/,
		\@bits,
	);

	return $self->refresh;
}

sub delete {
	my $self = shift;

	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $table = $self->_table;
	$self->_mysql->doQuery(
		qq/DELETE FROM $table WHERE $where;/,
		$pk_bits,
	);

	return;
}

sub refresh {
	my ($self) = @_;

	my $table    = $self->_table;
	my $fieldDetails = $self->_field_details;
	my $fields   = join ', ', keys(%$fieldDetails);
	my ($where, $pk_bits) = $self->_primary_key_where_clause;

	my $query = qq/SELECT $fields FROM $table WHERE $where;/;
	my $rows = $self->_mysql->fetchRows($query, $pk_bits);
	if (@$rows) {
		my $found = $rows->[0];
		$_[0] = $self->promote($found);
	}
	else {
		$_[0] = undef;
	}

	return $_[0];
}

sub all {
	my $invocant = shift;
	my @results = $invocant->search({}, {});

	return @results;
}

sub promote {
	my $invocant = $_[0];
	my $class = Scalar::Util::blessed($invocant) || $invocant;

	my $objClass = $class->__dynamicSubclass($_[1]);

	$_[1] = bless $_[1], $objClass;
	return $_[1];
}

sub asHashRef {
	my $self = shift;
	my $fieldDetails = $self->_field_details();

	my $hash = {};
	foreach my $field (keys %$fieldDetails) {
		my $val = $self->{$field};
		if ($val && $fieldDetails->{$field}{Type} eq 'json') {
			$hash->{$field} = JSON::decode_json($val);
		}
		else {
			$hash->{$field} = $val;
		}
	}

	return $hash;
}

sub atomic {
	my $invocant = shift;
	return $invocant->_mysql->atomic(@_);
}

sub _mysql {
	return 'ConvoTreeEngine::Mysql';
}

1;