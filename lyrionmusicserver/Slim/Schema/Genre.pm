package Slim::Schema::Genre;


use strict;
use base 'Slim::Schema::DBI';
use Scalar::Util qw(blessed);

use Slim::Schema::ResultSet::Genre;

use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $myClassicalGenreMap;
my $myClassicalGenreIds;

{
	my $class = __PACKAGE__;

	$class->table('genres');

	$class->add_columns(qw(
		id
		name
		namesort
		namesearch
		musicmagic_mixable
	));

	$class->set_primary_key('id');
	$class->add_unique_constraint('namesearch' => [qw/namesearch/]);

	$class->has_many('genreTracks' => 'Slim::Schema::GenreTrack' => 'genre');

	$class->utf8_columns(qw/name namesort/);

	$class->resultset_class('Slim::Schema::ResultSet::Genre');
}

sub loadMyClassicalGenreMap {
	my $prefs = preferences('server');
	%$myClassicalGenreMap = map {$_ => 1} split(/\s*,\s*/, uc($prefs->get('myClassicalGenres')));
	if ( !%$myClassicalGenreMap ) {
		$myClassicalGenreIds = undef;
		return;
	} else {
		# also load genre ids from database
		my @genreNames = keys %$myClassicalGenreMap;
		my $dbh = Slim::Schema->dbh;
		my $sql = 'SELECT GROUP_CONCAT(id) FROM genres WHERE UPPER(name) IN (' . join(', ', map {'?'} @genreNames) . ')';
		my $sth = $dbh->prepare_cached($sql);
		$sth->execute(@genreNames);
		($myClassicalGenreIds) = $sth->fetchrow_array;
		$sth->finish;
	}
}

sub isMyClassicalGenre {
	my ($class, $genres, $sep) = @_;

	loadMyClassicalGenreMap() if !$myClassicalGenreMap;

	return (grep {
		$myClassicalGenreMap->{uc($_)}
	} Slim::Music::Info::splitTag($genres, $sep)) ? 1 : 0;
}

sub myClassicalGenreIds {
	loadMyClassicalGenreMap() if !$myClassicalGenreMap;
	return $myClassicalGenreIds;
}

sub url {
	my $self = shift;

	return sprintf('db:genre.name=%s', URI::Escape::uri_escape_utf8($self->name));
}

sub tracks {
	my $self = shift;

	return $self->genreTracks->search_related('track' => @_);
}

sub displayAsHTML {
	my ($self, $form, $descend, $sort) = @_;

	$form->{'text'} = $self->name;
}

sub add {
	my $class = shift;
	my $genre = shift;
	my $trackId = shift;

	# Using native DBI here to improve performance during scanning
	# and because DBIC objects are not needed here
	# This is around 20x faster than using DBIC
	my $dbh = Slim::Schema->dbh;

	for my $genreSub (Slim::Music::Info::splitTag($genre)) {

		my $namesort = Slim::Utils::Text::ignoreCaseArticles($genreSub);
		my $namesearch = Slim::Utils::Text::ignoreCase($genreSub, 1);

		my $sth = $dbh->prepare_cached( 'SELECT id FROM genres WHERE namesearch = ?' );
		$sth->execute( $namesearch );
		my ($id) = $sth->fetchrow_array;
		$sth->finish;

		if ( !$id ) {
			$sth = $dbh->prepare_cached( qq{
				INSERT INTO genres
				(namesort, name, namesearch)
				VALUES
				(?, ?, ?)
			} );
			$sth->execute( $namesort, $genreSub, $namesearch );
			$id = $dbh->last_insert_id(undef, undef, undef, undef);
		}

		$sth = $dbh->prepare_cached( qq{
			REPLACE INTO genre_track
			(genre, track)
			VALUES
			(?, ?)
		} );
		$sth->execute( $id, $trackId );
	}

	return;
}

sub rescan {
	my ( $class, @ids ) = @_;

	my $dbh = Slim::Schema->dbh;

	my $log = logger('scan.scanner');

	for my $id ( @ids ) {
		my $sth = $dbh->prepare_cached( qq{
			SELECT COUNT(*) FROM genre_track WHERE genre = ?
		} );
		$sth->execute($id);
		my ($count) = $sth->fetchrow_array;
		$sth->finish;

		if ( !$count ) {
			main::DEBUGLOG && $log->is_debug && $log->debug("Removing unused genre: $id");

			$dbh->do( "DELETE FROM genres WHERE id = ?", undef, $id );
		}
	}
}

1;

__END__
