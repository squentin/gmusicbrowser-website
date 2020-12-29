VERSION = '0.1'
IFACE_NAME = 'org.gmusicbrowser'
IFACE_PATH = '/org/gmusicbrowser'

import CurrentSong

class Gmusicbrowser ( CurrentSong.DbusBase ):
    '''Gmusicbrowser Interface'''

    def __init__( self ):
        CurrentSong.DbusBase.__init__( self, IFACE_NAME, self.setInterface )

        try: self.iface
        except: self.iface = None

    def setInterface( self ):
	self.iface = self.bus.get_object( IFACE_NAME, IFACE_PATH )

    def check(self):
        if not self.iface or not self.isNameActive(IFACE_NAME):
            return

        dict = self.iface.CurrentSong()
        if dict['title'] != self.title or \
           dict['album'] != self.album or \
           dict['artist'] != self.artist:
            self.title = dict['title']
            self.album = dict['album']
            self.artist = dict['artist']
            return True
        else:
            return False

    def isPlaying(self):
        if not self.isRunning(): return False
        if not self.iface: return False
	return bool( self.iface.Playing() )

    def isRunning(self):
        return self.isNameActive(IFACE_NAME)

    def getCoverPath( self ):
        if self.iface:
            return self.iface.GetAlbumCover(self.album)
        else:
            return None

