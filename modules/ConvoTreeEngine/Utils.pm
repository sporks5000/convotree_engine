package ConvoTreeEngine::Utils;

{
	my %IGNORE_METHODS = map { $_ => 1 } qw(ISA);
	my %CLASS_LOADED;

	no strict 'refs';
	sub require {
		if ($_[0] && !ref $_[0] && $_[0] eq 'ConvoTreeEngine::Utils') {
			shift;
		}
		my ($class) = @_;

		return if ($CLASS_LOADED{$class});

		no warnings 'once';
		eval "require $class";
		if (my $ex = $@) {
			if ("$ex" =~ m/you may need to install the $class module/) {
				if (%{"$class\::"} && grep { $_ !~ /::$/ && ! $IGNORE_METHODS{$_} } keys %{"$class\::"}) {
					$CLASS_LOADED{$class} = 1;
					return;
				}
			}
			die "$ex";
		}

		return $CLASS_LOADED{$class} = 1;
	}
}

=head2 compare

Given two values...

* If they are both undef, return true
* If they are both numbers and numerically equal, return true
* If they are both string equal, return true
* Otherwise return false.

=cut

sub compare {
	shift; ### ConvoTreeEngine::Utils class. We can ignore.
	my $arg1  = shift;
	my $arg2  = shift;

	if (defined $arg1 xor defined $arg2) {
		return 0;
	}
	if (!defined $arg1) {
		return 1;
	}
	my $resp = eval {
		local $SIG{__WARN__} = sub {
			die;
		};
		if ($arg1 == $arg2) {
			return 1;
		}
		return 0;
	};
	if ($@) {
		if ($arg1 eq $arg2) {
			return 1;
		}
		return 0;
	}
	return $resp;
}

=head2 convert_to_array

Given a variable that is allowed to be interpreted as an arrayref or something that
is not na arrayref, convert it to an arrayref. Optionally given a second variable
which may or may not be an arrayref, add either it or the contests of its arrayref
to the original arrayref. If neither variable is defined, return an empty arrayref.

=cut

sub convert_to_array {
	shift; ### ConvoTreeEngine::Utils class. We can ignore.
	my $toConvert = shift;
	my $toAdd     = shift;

	if (defined $toAdd) {
		$toAdd = [$toAdd] unless ref($toAdd || '') eq 'ARRAY';
	}

	if (defined $toConvert) {
		$toConvert = [$toConvert] unless ref($toConvert || '') eq 'ARRAY';
		if ($toAdd) {
			push @$toConvert, @$toAdd;
		}
	}
	elsif ($toAdd) {
		$toConvert = $toAdd;
	}
	else {
		$toConvert = [];
	}

	return $toConvert;
}

=head2 createROAccessors

Given a list of field names, assume that the class represents a hashref object where each
field name is a key on that object and create a method for each field name where the value
of that key is returned.

=cut

sub createROAccessors {
	shift; ### Unreasonable::Utils class. We can ignore.
	my $class  = shift;
	my @fields = @_;

	no strict 'refs';

	foreach my $field (@fields) {
		my $symbol_name = "${class}::$field";
		next if defined &{$symbol_name};
		*{$symbol_name} = sub {
			return shift->{$field};
		};
	}

	return;
}

=head2 createRWAccessors

Given a list of field names, assume that the class represents a hashref object where each
field name is a key on that object and create a method for each field name where the value
of that key is returned. Assuming there's no indicator that the field should be read only,
also make it so that if a value is passed in, the object's key is updated to that value.

If the class has an "update" method, either in itself or inherited from a parent class, use
that update method when attempting to update the value of a key.

=cut

sub createRWAccessors {
	shift; ### Unreasonable::Utils class. We can ignore.
	my $class  = shift;
	my @fields = @_;

	my %roFields;
	no strict 'refs';
	if (defined &{"${class}::_read_only_fields"}) {
		%roFields = map {$_ => 1} $class->_read_only_fields;
	}

	my $update;
	$update = 1 if $class->can('update');

	foreach my $field (@fields) {
		my $symbol_name = "${class}::$field";
		next if defined &{$symbol_name};
		if ($roFields{$field}) {
			*{$symbol_name} = sub {
				return shift->{$field};
			};
		}
		elsif ($update) {
			*{$symbol_name} = sub {
				my $self = shift;
				if (@_) {
					my $value = shift;
					$self->update({$field => $value});
					return $self->{$field};
				}
				return $self->{$field};
			};
		}
		else {
			*{$symbol_name} = sub {
				my $self = shift;
				if (@_) {
					my $value = shift;
					return $self->{$field} = $value;
				}
				return $self->{$field};
			};
		}
	}

	return;
}

1;