package Slim::Utils::OS::RedHat;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use FindBin qw($Bin);

use base qw(Slim::Utils::OS::Linux);

sub initDetails {
	my $class = shift;

	$class->{osDetails} = $class->SUPER::initDetails();

	$class->{osDetails}->{isRedHat} = 1;

	return $class->{osDetails};
}

=head2 dirsFor( $dir )

Return OS Specific directories.

Argument $dir is a string to indicate which of the Lyrion Music Server directories we
need information for.

=cut

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = ();

	if ($dir =~ /^(?:oldprefs|updates)$/) {

		push @dirs, $class->SUPER::dirsFor($dir);

	} elsif ($dir =~ /^(?:Firmware|Graphics|HTML|IR|SQL|lib|Bin)$/) {

		push @dirs, "/usr/share/lyrionmusicserver/$dir";

	} elsif ($dir eq 'Plugins') {

		push @dirs, $class->SUPER::dirsFor($dir);
		push @dirs, "/usr/share/lyrionmusicserver/Plugins";
		push @dirs, "/usr/lib/perl5/vendor_perl/Slim/Plugin";

	} elsif ($dir =~ /^(?:strings|revision|repositories)$/) {

		push @dirs, "/usr/share/lyrionmusicserver";

	} elsif ($dir eq 'libpath') {

		push @dirs, "/usr/share/lyrionmusicserver";

	} elsif ($dir =~ /^(?:types|convert)$/) {

		push @dirs, "/etc/lyrionmusicserver";

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || "/var/lib/lyrionmusicserver/prefs";

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || "/var/log/lyrionmusicserver";

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || "/var/lib/lyrionmusicserver/cache";

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		push @dirs, '';

	} else {

		warn "dirsFor: Didn't find a match request: [$dir]\n";
	}

	return wantarray() ? @dirs : $dirs[0];
}


sub scanner {
	return '/usr/libexec/lyrionmusicserver-scanner';
}

sub gdresized {
	return '/usr/libexec/lyrionmusicserver-resized';
}

sub canAutoUpdate { $_[0]->SUPER::runningFromSource ? 0 : 1 }
sub installerExtension { 'rpm' };
sub installerOS { 'rpm' }

sub getUpdateParams {
	my ($class, $url) = @_;

	if ($url) {
		Slim::Utils::OS::Linux::signalUpdateReady($url);
	}

	return;
}


1;
