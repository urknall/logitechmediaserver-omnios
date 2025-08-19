package Slim::Web::Settings::Server::Index;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use HTTP::Status qw(RC_MOVED_TEMPORARILY);

use base qw(Slim::Web::Settings);
use Slim::Utils::Prefs;

my $prefs = preferences('server');

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('settings/index.html');
}

sub handler {
	my ($class, $client, $paramRef, $pageSetup, $httpClient, $response) = @_;

	# redirect to the setup wizard if it has never been run before
	if (!$prefs->get('wizardDone')) {
		$response->code(RC_MOVED_TEMPORARILY);
		$response->header('Location' => '/settings/server/wizard.html');
		return Slim::Web::HTTP::filltemplatefile($class->page, $paramRef);
	}

	return $class->SUPER::handler($client, $paramRef);
}

1;

__END__
