package ConvoTreeEngine::Utils;

{
	my %IGNORE_METHODS = map { $_ => 1 } qw(ISA);
	my %CLASS_LOADED;

	no strict 'refs';
	sub require {
		my ($invocant, $class) = @_;

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

=head2 convert_to_array

Given a variable that is allowed to be interpreted as an arrayref or something that
is not na arrayref, convert it to an arrayref. Optionally given a second variable
which may or may not be an arrayref, add either it or the contests of its arrayref
to the original arrayref. If neither variable is defined, return an empty arrayref.

=cut

sub convert_to_array {
	my $invocant  = shift;
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

1;