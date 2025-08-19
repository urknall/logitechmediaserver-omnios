package Slim::Utils::OS::Win32;

# Logitech Media Server Copyright 2001-2024 Logitech.
# Lyrion Music Server Copyright 2024 Lyrion Community.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Cwd;
use File::Basename qw(dirname);
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Sys::Hostname qw(hostname);
use Win32;
use Win32::OLE;
use Win32::OLE::NLS;
use Win32::TieRegistry ('Delimiter' => '/');

Win32::OLE->Option(CP => Win32::OLE::CP_UTF8);

use base qw(Slim::Utils::OS);

my $driveList  = {};
my $driveState = {};
my $writablePath;

sub name {
	return 'win';
}

sub initDetails {
	my $class = shift;

	# better version detection than relying on Win32::GetOSName()
	# http://msdn.microsoft.com/en-us/library/ms724429(VS.85).aspx
	my ($string, $major, $minor, $build, $id, $spmajor, $spminor, $suitemask, $producttype) = Win32::GetOSVersion();

	$class->{osDetails} = {
		'os'     => 'Windows',
		'osName' => (Win32::GetOSName())[0],
		'osArch' => Win32::GetChipName(),
		'uid'    => Win32::LoginName(),
		'fsType' => (Win32::FsType())[0],
	};

	# Do a little munging for pretty names.
	$class->{osDetails}->{'osName'} =~ s/Win/Windows /;
	$class->{osDetails}->{'osName'} =~ s/\/.Net//;
	$class->{osDetails}->{'osName'} =~ s/2003/Server 2003/;

	# TODO: remove this code as soon as Win32::GetOSName supports latest Windows versions

	# The version numbers for Windows 7 and Windows Server 2008 R2 are identical; the PRODUCTTYPE field must be used to differentiate between them.
	if ($major == 6 && $minor == 1 && $producttype != 1) {
		$class->{osDetails}->{'osName'} = 'Windows 2008 Server R2';
	}

	# The version numbers for Windows 8 onwards are identical, Win32.pm has not been updated to cover these
	# https://msdn.microsoft.com/en-us/library/windows/desktop/ms724832(v=vs.85).aspx
	elsif (($major == 6 && $minor == 2) || ($major == 10 && $minor == 0)) {

		if ( my $wmi = Win32::OLE->GetObject( "WinMgmts://./root/cimv2" ) ) {
			if ( my $list = $wmi->InstancesOf( "Win32_OperatingSystem" ) ) {

				for my $item ( Win32::OLE::in $list ) {

					my $version = $item->{Version};
					if ( my ($major, $minor, $build) = $version =~ /(\d+)\.(\d+)\.(\d+)/ ) {
						if ($major == 6 && $minor == 2) {
							$class->{osDetails}->{'osName'} = $producttype != 1 ? 'Windows 2012 Server' : 'Windows 8';
						}
						elsif ($major == 6 && $minor == 3) {
							$class->{osDetails}->{'osName'} = $producttype != 1 ? 'Windows 2012 Server R2' : 'Windows 8.1';
						}
						elsif ($major == 10 && $minor == 0 && $producttype != 1 && $build && $build >= 20348) {
							$class->{osDetails}->{'osName'} = 'Windows 2022 Server';
						}
						elsif ($major == 10 && $minor == 0 && $build && $build >= 22000) {
							$class->{osDetails}->{'osName'} = $producttype != 1 ? 'Windows 2022 Server' : 'Windows 11';
						}
						elsif ($major == 10 && $minor == 0) {
							$class->{osDetails}->{'osName'} = $producttype != 1 ? 'Windows 2016 Server' : 'Windows 10';
						}
						else {
							main::INFOLOG && warn "Unknown Windows version - Major: $major, Minor: $minor\n";
							$class->{osDetails}->{'osName'} = sprintf('Windows %s(2.%s.%s, %s)', ($producttype != 1 ? 'Server ' : ''), $major, $minor, $producttype);
						}
						last;
					}
				}

			}
		}
	}

	# Windows 2003 && suitemask 0x00008000 -> WHS
	# http://msdn.microsoft.com/en-us/library/ms724833(VS.85).aspx
	elsif ($major == 5 && $minor == 2
			&& $suitemask && $suitemask & 0x00008000) {
		$class->{osDetails}->{'osName'} = 'Windows Home Server';
		$class->{osDetails}->{'isWHS'} = 1;
	}

	# give some fallback value
	$class->{osDetails}->{osName} ||= sprintf('Windows (%s, %s, %s)', $major, $minor, $producttype);

	# This covers Vista or later
	$class->{osDetails}->{'isWin6+'} = ($major >= 6);

	return $class->{osDetails};
}

sub initSearchPath {
	my $class = shift;

	$class->SUPER::initSearchPath(@_);

	# Add the location of perl.exe to the helper applications folder search path.
	if ($^X =~ /perl\.exe/) {
		Slim::Utils::Misc::addFindBinPaths(dirname($^X));
	}
}

sub canDBHighMem { 1 }

sub dirsFor {
	my ($class, $dir) = @_;

	my @dirs = $class->SUPER::dirsFor($dir);

	if ($dir =~ /^(?:strings|revision|convert|types|repositories)$/) {

		push @dirs, $Bin;

	} elsif ($dir eq 'log') {

		push @dirs, $::logdir || $class->writablePath('Logs');

	} elsif ($dir eq 'cache') {

		push @dirs, $::cachedir || $class->writablePath('Cache');

	} elsif ($dir eq 'oldprefs') {

		if ($::prefsfile && -r $::prefsfile) {

			push @dirs, $::prefsfile;
		}

		else {

			if ($class->{osDetails}->{'isWin6+'} && -r catdir($class->writablePath(), 'slimserver.pref')) {

				push @dirs, catdir($class->writablePath(''), 'slimserver.pref');
			}

			elsif (-r catdir($Bin, 'slimserver.pref'))  {

				push @dirs, catdir($Bin, 'slimserver.pref');
			}
		}

	} elsif ($dir eq 'base') {

		push @dirs, $class->installPath();

	} elsif ($dir eq 'prefs') {

		push @dirs, $::prefsdir || $class->writablePath('prefs');

	} elsif ($dir =~ /^(?:music|playlists)$/) {

		my $path;
		my $fallback;

		if ($dir =~ /^(?:music|playlists)$/) {
			$path = Win32::GetFolderPath(Win32::CSIDL_MYMUSIC) unless $path;
			$fallback = 'My Music';
		}

		# fall back if no path or invalid path is returned
		if (!$path || $path eq Win32::GetFolderPath(0)) {

			my $swKey = $Win32::TieRegistry::Registry->Open(
				'CUser/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/',
				{
					Access => Win32::TieRegistry::KEY_READ(),
					Delimiter =>'/'
				}
			);

			if (defined $swKey) {
				if (!($path = $swKey->{$fallback})) {
					if ($path = $swKey->{'Personal'}) {
						$path = catdir($path, $fallback);
					}
				}
			}
		}

		if ($path && $dir eq 'playlists') {
			$path = catdir($path, 'Playlists');
		}

		push @dirs, $path;

	# we don't want these values to return a value
	} elsif ($dir =~ /^(?:libpath)$/) {

	} else {

		push @dirs, catdir($Bin, $dir);
	}

	return wantarray() ? @dirs : $dirs[0];
}

sub decodeExternalHelperPath {
	return Win32::GetShortPathName($_[1]);
}


=head2 getFileName()

Apply some magic to expand short file names, read non-latin names on non-western Windows etc.

=cut

sub getFileName {
	my $class = shift;
	my $path  = shift;

	my $locale = Slim::Utils::Unicode->currentLocale();
	my $fsObj;

	if ($locale ne 'cp1252') {
		$fsObj = Win32::OLE->new('Scripting.FileSystemObject') or Slim::Utils::Log::logger('database.info')->error("$@ - cannot load Scripting.FileSystemObject?!?");
	}

	# display full name if we got a Windows 8.3 file path with a tilde in it
	if ($path =~ /~\d+(\.|$)/ && $path =~ /\\|\//) {

		if (my $n = Win32::GetLongPathName($path)) {
			$n = File::Basename::basename($n);
			main::INFOLOG && Slim::Utils::Log::logger('database.info')->info("Expand short name returned by readdir() to full name: $path -> $n");

			$path = $n;
		}

	}

	elsif ( $fsObj && -d $path && (my $folderObj = $fsObj->GetFolder($path)) ) {

		main::INFOLOG && Slim::Utils::Log::logger('database.info')->info("Running Windows with non-Western codepage, trying to convert folder name: $path -> " . $folderObj->{Name});
		$path = $folderObj->{Name};
	}

	elsif ( $fsObj && -f $path && (my $fileObj = $fsObj->GetFile($path)) ) {

		main::INFOLOG && Slim::Utils::Log::logger('database.info')->info("Running Windows with non-Western codepage, trying to convert file name: $path -> " . $fileObj->{Name});
		$path = $fileObj->{Name};
	}

	else {
		# bug 16683 - experimental fix
		# Decode pathnames that do not have '~' as they may have locale-encoded characters in them
		$path = Slim::Utils::Unicode::utf8decode_locale($path);
	}

	return $path;
}

sub localeDetails {
	eval { use POSIX qw(LC_TIME); };
	require Win32::Locale;

	my $langid = Win32::OLE::NLS::GetSystemDefaultLCID();
	my $lcid   = Win32::OLE::NLS::MAKELCID($langid);
	my $linfo  = Win32::OLE::NLS::GetLocaleInfo($lcid, Win32::OLE::NLS::LOCALE_IDEFAULTANSICODEPAGE());

	my $lc_ctype = "cp$linfo";
	my $locale   = Win32::Locale::get_locale($langid);
	my $lc_time  = POSIX::setlocale(LC_TIME, $locale);

	return ($lc_ctype, $lc_time);
}

sub noCaseFilename {
	my ($class, $name) = @_;
	return Slim::Utils::Unicode::utf8encode_locale($class->SUPER::noCaseFilename($name));
}

sub getSystemLanguage {
	my $class = shift;

	require Win32::Locale;

	$class->_parseLanguage(Win32::Locale::get_language());
}

sub dontSetUserAndGroup { 1 }

sub getProxy {
	my $class = shift;
	my $proxy = '';

	# on Windows read Internet Explorer's proxy setting
	my $ieSettings = $Win32::TieRegistry::Registry->Open(
		'CUser/Software/Microsoft/Windows/CurrentVersion/Internet Settings',
		{
			Access => Win32::TieRegistry::KEY_READ(),
			Delimiter =>'/'
		}
	);

	if (defined $ieSettings && hex($ieSettings->{'ProxyEnable'})) {
		$proxy = $ieSettings->{'ProxyServer'};
	}

	return $proxy || $class->SUPER::getProxy();
}

sub getDefaultGateway {
	my $route = `route print -4`;
	while ( $route =~ /^\s*0\.0\.0\.0\s+\d+\.\d+\.\d+\.\d+\s+(\d+\.\d+\.\d+\.\d+)/mg ) {
		if ( Slim::Utils::Network::ip_is_private($1) ) {
			return $1;
		}
	}

	return;
}

sub ignoredItems {
	return (
		# Items we should ignore  on a Windows volume
		'System Volume Information' => '/',
		'RECYCLER'     => '/',
		'Recycled'     => '/',
		'$Recycle.Bin' => '/',
	);
}


=head2 getDrives()

Returns a list of drives available to the server, filtering out floppy drives etc.

=cut

sub getDrives {

	if (!defined $driveList->{ttl} || !$driveList->{drives} || $driveList->{ttl} < time) {
		require Win32API::File;;

		my @drives = grep {
			s/\\//;

			my $driveType = Win32API::File::GetDriveType($_);
			Slim::Utils::Log::logger('os.paths')->debug("Drive of type '$driveType' found: $_");

			# what USB drive is considered REMOVABLE, what's FIXED?
			# have an external HDD -> FIXED, USB stick -> REMOVABLE
			# would love to filter out REMOVABLEs, but I'm not sure it's save
			#($driveType != DRIVE_UNKNOWN && $driveType != DRIVE_REMOVABLE);
			($driveType != Win32API::File->DRIVE_UNKNOWN && /[^AB]:/i);
		} Win32API::File::getLogicalDrives();

		$driveList = {
			ttl    => time() + 60,
			drives => \@drives
		}
	}

	return @{ $driveList->{drives} };
}

=head2 isDriveReady()

Verifies whether a drive can be accessed or not

=cut

sub isDriveReady {
	my ($class, $drive) = @_;

	# shortcut - we've already tested this drive
	if (!defined $driveState->{$drive} || $driveState->{$drive}->{ttl} < time) {

		$driveState->{$drive} = {
			state => 0,
			ttl   => time() + 60	# cache state for a minute
		};

		# don't check inexisting drives
		if (scalar(grep /$drive/, $class->getDrives()) && -r $drive) {
			$driveState->{$drive}->{state} = 1;
		}

		Slim::Utils::Log::logger('os.paths')->debug("Checking drive state for $drive");
		Slim::Utils::Log::logger('os.paths')->debug('      --> ' . ($driveState->{$drive}->{state} ? 'ok' : 'nok'));
	}

	return $driveState->{$drive}->{state};
}

=head2 installPath()

Returns the base installation directory of Lyrion Music Server.

=cut

sub installPath {

	# Try and find it in the registry.
	# This is a system-wide registry key.
	my $swKey = $Win32::TieRegistry::Registry->Open(
		'LMachine/Software/Lyrion/server/',
		{
			Access => Win32::TieRegistry::KEY_READ(),
			Delimiter =>'/'
		}
	);

	if (defined $swKey && $swKey->{'Path'}) {
		return $swKey->{'Path'} if -d $swKey->{'Path'};
	}

	# Otherwise look in the standard location.
	# search in legacy SlimServer folder, too
	my $installDir;
	PF: foreach my $programFolder ($ENV{ProgramFiles}, 'C:/Program Files') {
		foreach my $ourFolder ('Lyrion', 'Squeezebox') {

			$installDir = File::Spec->catdir($programFolder, $ourFolder);
			last PF if (-d $installDir);

			$installDir = '';
		}
	}

	return $installDir || getcwd();

	return '';
}


=head2 writablePath()

Returns a path which is expected to be writable by all users on Windows without virtualisation on Vista.
This should mean that the server always sees consistent versions of files under this path.

=cut

sub writablePath {
	my ($class, $folder) = @_;
	my $path;

	unless ($writablePath) {

		# the installer is writing the data folder to the registry - give this the first try
		my $swKey = $Win32::TieRegistry::Registry->Open(
			'LMachine/Software/Lyrion/server/',
			{
				Access => Win32::TieRegistry::KEY_READ(),
				Delimiter =>'/'
			}
		);

		if (defined $swKey && $swKey->{'DataPath'}) {
			$writablePath = $swKey->{'DataPath'};
		}

		else {
			# second attempt: use the Windows API (recommended by MS)
			# use the "Common Application Data" folder to store Lyrion Music Server configuration etc.
			$writablePath = Win32::GetFolderPath(Win32::CSIDL_COMMON_APPDATA);

			# fall back if no path or invalid path is returned
			if (!$writablePath || $writablePath eq Win32::GetFolderPath(0)) {

				# third attempt: read the registry's compatibility value
				# NOTE: this key has proved to be wrong on some Vista systems
				# only here for backwards compatibility
				$swKey = $Win32::TieRegistry::Registry->Open(
					'LMachine/Software/Microsoft/Windows/CurrentVersion/Explorer/Shell Folders/',
					{
						Access => Win32::TieRegistry::KEY_READ(),
						Delimiter =>'/'
					}
				);

				if (defined $swKey && $swKey->{'Common AppData'}) {
					$writablePath = $swKey->{'Common AppData'};
				}

				elsif ($ENV{'ProgramData'}) {
					$writablePath = $ENV{'ProgramData'};
				}

				# this point hopefully is never reached, as on most systems the program folder isn't writable...
				else {
					$writablePath = $Bin;
				}
			}

			$writablePath = catdir($writablePath, 'Lyrion') unless $writablePath eq $Bin;

			# store the key in the registry for future reference
			$swKey = $Win32::TieRegistry::Registry->Open(
				'LMachine/Software/Lyrion/software/',
				{
					Delimiter =>'/'
				}
			);

			if (defined $swKey && !$swKey->{'DataPath'}) {
				$swKey->{'DataPath'} = $writablePath;
			}
		}

		if (! -d $writablePath) {
			mkdir $writablePath;
		}
	}

	$path = catdir($writablePath, $folder);

	mkdir $path unless -d $path;

	return $path;
}

=head2 pathFromShortcut( $path )

Return the filepath for a given Windows Shortcut

=cut

sub pathFromShortcut {
	my $class    = shift;
	my $fullpath = Slim::Utils::Misc::pathFromFileURL(shift);

	require Win32::Shortcut;

	my $path     = "";
	my $shortcut = Win32::Shortcut->new($fullpath);

	if (defined($shortcut)) {

		$path = $shortcut->Path();

		# the following pattern match throws out the path returned from the
		# shortcut if the shortcut is contained in a child directory of the path
		# to avoid simple loops, loops involving more than one shortcut are still
		# possible and should be dealt with somewhere, just not here.
		if (defined($path) && !$path eq "" && $fullpath !~ /^\Q$path\E/i) {

			$path = Slim::Utils::Misc::fileURLFromPath($path);

			#collapse shortcuts to shortcuts into a single hop
			if (Slim::Music::Info::isWinShortcut($path)) {
				$path = $class->pathFromShortcut($path);
			}

		} else {

			Slim::Utils::Log::logger('os.files')->error("Bad path in $fullpath - path was: [$path]");

			return;
		}

	} else {

		Slim::Utils::Log::logger('os.files')->error("Shortcut $fullpath is invalid");

		return;
	}

	return $path;
}

=head2 fileURLFromShortcut( $shortcut )

	Special case to convert a windows shortcut to a normalised file:// url.

=cut

sub fileURLFromShortcut {
	my ($class, $path) = @_;
	return Slim::Utils::Misc::fixPath( $class->pathFromShortcut($path) );
}

=head2 getShortcut( $shortcut )

	Return a shortcut's name and the target URL

=cut

sub getShortcut {
	my ($class, $path) = @_;

	my $name = Slim::Music::Info::fileName($path);
	$name =~ s/\.lnk$//i;

	return ( $name, $class->fileURLFromShortcut($path) );
}

=head2 setPriority( $priority )

Set the priority for the server. $priority should be -20 to 20

=cut

sub setPriority {}

=head2 getPriority( )

Get the current priority of the server. Disabled on Windows.

=cut

sub getPriority {}


1;
