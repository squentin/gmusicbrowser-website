package GMB::Plugin::GMBWeb;
use Socket;
use strict;
use warnings;
use constant
{	PID	=> 'GMBWeb',
	name	=> 'Web interface',
	EOL	=> "\015\012",
};

::SetDefaultOptions(PID, port => 8080);
my $socket;
my $active;

$::Plugins{&PID}=__PACKAGE__;

sub init
{	$active=1;
	Listen();
}
sub end
{	$active=0;
	Stop();
}
sub prefbox
{	my $vbox=Gtk2::VBox->new(::FALSE, 2);
	my $label1=Gtk2::Label->new('Web interface plugin v0.1');
	my $label2=Gtk2::Label->new('');
	$label2->set_line_wrap(::TRUE);
	my $entry=::NewPrefEntry('PLUGIN_'.PID.'_port',_"listen to port :",\&Listen);
	$vbox->pack_start($_,::FALSE,::FALSE,2) for $label1,$label2,$entry;
	return $vbox;
}

sub Listen
{	return unless $active;
	Stop();
	my $error;
	my $port=$::Options{'PLUGIN_'.PID.'_port'};
	{	last unless $port;
		my $proto=getprotobyname('tcp');
		socket($socket, PF_INET, SOCK_STREAM, $proto)	or $error="socket: $!" and last;
		setsockopt($socket, SOL_SOCKET, SO_REUSEADDR, pack('l',1) ) or $error="setsockopt: $!" and last;
		bind($socket, sockaddr_in($port, INADDR_ANY))	or $error="bind: $!" and last;
		listen($socket,SOMAXCONN)			or $error="listen: $!" and last;
		logmsg("server started on port $port");
		Glib::IO->add_watch(fileno($socket),'in', \&Connection);
	}
	if ($error) {warn $error;Stop();}
}
sub Stop
{	close $socket if $socket;
	$socket=undef;
}

sub Connection
{	return 0 unless $active;
	my $client;
	my $paddr = accept($client,$socket);
	my($port2,$iaddr) = sockaddr_in($paddr);
	logmsg('connection from ',inet_ntoa($iaddr), " at port $port2");
	my %headers; my $request; my $post;
	{	local $/=EOL;
		$request=<$client>;
		chomp $request;
		while (<$client>)
		{	last if $_ eq EOL;chomp;
			$headers{$1}=$2 if m/^([^:]+): (.*)/;
		}
		if ($request=~m/^POST/ && $headers{'Content-Length'})
		{	read $client,$post,$headers{'Content-Length'};
		}
	}
	my $permlevel;
	my ($content,$title,$mime,$result);
	my $layer=':raw';
	if ($post && $post=~m/^song=(\d+)/) { ::Select(undef,undef,$1,'play'); }
	if ($request=~m#^(?:GET|POST) (.*) HTTP/1\.\d+$#)
	{	warn "path=$1\n";
		($content,$title,$mime,$result)=makepage($1,$permlevel);
		if (defined $content)
		{	$result||='200 OK';
			$title||='GMBweb';
			my $css='
 <style type="text/css">
 body { padding: 1% 2% 0 2%; }
 #header {
	position: relative;
	height: 3em;
	padding: 1em 0 1em 0;
	border-bottom: 1px solid #bbb;
 }
 #header h1 {	position: absolute;
		top: 0;
		right: 10px;
		margin: 0;
		font-size: 36px;
		z-index: 10;
 }
 #header ul {	position: absolute;
		bottom: 0;
		left: 0;
		margin: 0;
		padding: 0 15px 0 0;
		list-style: none;
		z-index: 9;
 }
 #header li {
	display: table-cell;
	padding: 4px 10px 4px 10px;
 }
 #header ul a {
	font-weight: bold;
	color: #000;
	text-decoration: none;
 }
 #header ul li:hover a { color: #47f; }
 ul { list-style: none; }
 .song {
 	background-color:#fff;
   	border-style: none;
	cursor: pointer;
 }
	/*		div.container{ width:100%; clear:both; }
			div.playing{ width:40%; float:right; border:1px solid black; padding:1em; }
			div logo{ width:20%; float:left;  }
			div.menu{ width:20%; border:1px solid black; float:right; padding:1em; }
			div.page{ float:left; width:70% }*/
 </style>';
			my $header='<div id="header"><h1>'.makelogo().'</h1><ul>'.makemenu().'</ul></div>';
			my $playing='<div class="playing">'.makeplaying().'</div>';
			$content='<html><head><meta content="text/html; charset=UTF-8">'.$css.'<title>'.$title.'</title></head><body>'.'<div class="container">'.$header.$playing.'<hr>'.'<div id="content">'.$content.'</div></div></body></html>' unless $mime;
			$layer=':utf8' unless $mime;
			$mime||='text/html';
		}
		else {$result||='404 Not Found'}
	}
	else {$result='400 Bad Request';}
	warn "$result (SongID=$::SongID)\n";
	my $answer=
	"HTTP/1.0 $result".EOL.
	'Server: GMBWeb/'.::VERSION.EOL.
	'Connection: close'.EOL;
	$answer.='Content-Length: '.length($content).EOL
#		.'Content-Type: '.$mime.'; charset=UTF-8'.EOL
		.EOL.$content if defined $content;
	binmode $client,$layer;
	send $client,$answer.EOL,0;
	close $client;
	1;
}

sub logmsg { print "GMBWeb: @_ at ", scalar localtime, "\n" }

sub makepage
{	my ($path,$permlevel)=@_;
	my ($page,$title,$mime,$result);
	if ($path eq '/') {$page='welcome to GMBWeb'}
	elsif ($path eq '/icon/gmusicbrowser.png') {open my$fh,'<',::PIXPATH.'gmusicbrowser.png'; my $buf; $page.=$buf while read $fh,$buf,1024*50;close $fh;$mime='image/png';}
	elsif ($path=~m#^/artist/?$#)
	{	$title='Artist list';
		$page=makeurllist('/artist/',sort keys %::Artist);
	}
	elsif ($path=~m#^/album/?$#)
	{	$title='Album list';
		$page=makeurllist('/album/',sort keys %::Album);
	}
	elsif ($path=~m#^/artist/(.*)$#)
	{	$page='<img src=/picture/artist/'.$1.'.jpg><br>';
		my $key=::decode_url($1);
		$title='Albums by '.::PangoEsc($key);
		return 'Artist not found' unless $::Artist{$key};
		$page='' unless $::Artist{$key}[::AAPIXLIST];
		$page.=makeurllist('/album/',sort keys %{$::Artist{$key}[::AAXREF]});
	}
	elsif ($path=~m#^/album/(.*)$#)
	{####	$page='<img src=/picture/album/'.$1.'.jpg><br>';
		$page='<img height="200" width="200" src=/picture/album/'.$1.'><br>';
		my $key=::decode_url($1);
		$title=::PangoEsc($key);
		return 'Album not found' unless $::Album{$key};
		$page='' unless $::Album{$key}[::AAPIXLIST];
		my @IDs=@{ $::Album{$key}[::AALIST] };
		$page.=makesonglist('%'.::SONG_TRACK.'. %'.::SONG_TITLE,\@IDs);
	}
	elsif ($path=~m#^/song/(\d+)$#)
	{	#FIXME check $permlevel
		return 'Song not found' unless $1<@::Songs && $::Songs[$1];
		::Select(undef,undef,$1,'play');
		#$page="Playing ".$::Songs[$::SongID][::SONG_TITLE].' by '.$::Songs[$::SongID][::SONG_ARTIST];
		$result='205 Reset Content';
	}
	elsif ($path=~m#^/picture/(artist|album)/(.*)$#)
####	elsif ($path=~m#^/picture/(artist|album)/(.*)\.jpg$#)
	{	my $aaref=$1 eq 'artist'?  \%::Artist : \%::Album;
		my $file=$aaref->{::decode_url($2)}[::AAPIXLIST];
		return unless $file;
		if ($Gtk2::VERSION < 1.120)
		{ if ($file=~m/\.mp3/i) {$page=ReadTag::PixbufFromMP3($file)}
		  else {open my$fh,'<',$file; my $buf; $page.=$buf while read $fh,$buf,1024*50;close $fh;}
		  return unless $page;
		  (undef,$mime)=EntryCover::_identify_pictype($page);
		}
		else # requires Gtk2::Gdk::Pixbuf::save_to_buffer added in perl-Gtk2 1.120
		{	my $pix=::PixBufFromFile($file);
			return unless $pix;
			my $w=my $h=200;
			my $ratio=$pix->get_width / $pix->get_height;
			if    ($ratio>1) {$h=int($w/$ratio);}
			elsif ($ratio<1) {$w=int($h*$ratio);}
			$pix=$pix->scale_simple($w, $h,'bilinear');
			$mime='image/jpeg';
			return unless eval {$page=$pix->save_to_buffer('jpeg', quality => '75'); }
		}
	}
	return ($page,$title,$mime,$result);
}

sub makeurllist
{	my $base=shift;
	my $page='<ul>';
	for (@_)
	{	$page.='<li><a href='.$base.::url_escape($_).'>'.::PangoEsc($_).'</a></li>';
	}
	$page.='</ul>';
	return $page;
}

sub makesonglist
{	my ($format,$IDs)=@_;
	my $page='';
	if (::VERSION<0.9496)
	{ ::SortList(::SONG_DISC.' '.::SONG_TRACK.' '.::SONG_UFILE,$IDs); }
	else
	{ ::SortList($IDs,::SONG_DISC.' '.::SONG_TRACK.' '.::SONG_UFILE); }
	for my $ID (@$IDs)
	{	my $s=$format;
		$s=~s/%(\d+)/::PangoEsc($::Songs[$ID][$1])/ge;
		$s='<b>'.$s.'</b>' if defined $::SongID && $::SongID==$ID;
		#$page.="<a href=/song/$ID onLoad=\"javascript:window.location.reload(true)\">".$s.'</a><br>';
		$page.='<form method=post  onsubmit="javascript:window.location.reload(true)"><button class=song type=submit name=song value='.$ID.'>'.$s.'</button></form>';
	}
	return $page;
}

sub makeplaying
{	my $ID=$::SongID;
	return '' unless defined $ID;
	my ($artist,$album,$title,$year,$length)=@{$::Songs[$ID]}[::SONG_ARTIST,::SONG_ALBUM,::SONG_TITLE,::SONG_DATE,::SONG_LENGTH];
	$length=sprintf '%d:%02d',$length/60,$length%60;
	$artist='<a href=/artist/'.::url_escape($artist).'>'.$artist.'</a>';
	$album='<a href=/album/'.::url_escape($album).'>'.$album.'</a>';
	return "$title ($length)<br>$artist<br>$album<br>";
}

sub makemenu
{	return '<li><a href="/artist">Artists</a></li><li><a href="/album">Albums</a></li>';
}

sub makelogo
{	return '<a href="http://squentin.free.fr/gmusicbrowser/gmusicbrowser.html"><img src=/icon/gmusicbrowser.png>gmusicbrowser</a>';
}

1
