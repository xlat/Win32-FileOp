package Win32::FileOp;

use vars qw($VERSION);
$Win32::FileOp::VERSION = '0.10.4';

use Win32::API;
use File::Find;
use File::Path;
use Cwd;
use strict ;# 'vars';
use Carp;

#http://Jenda.Krynicky.cz/
use Lazy;
use Win32::AbsPath qw(Relative2Absolute RelativeToAbsolute);

require Exporter;
@Win32::FileOp::ISA = qw(Exporter);

$Win32::FileOp::BufferSize = 65534;

my @FOF_flags = qw(
 FOF_SILENT FOF_RENAMEONCOLLISION FOF_NOCONFIRMATION FOF_ALLOWUNDO
 FOF_FILESONLY FOF_SIMPLEPROGRESS FOF_NOCONFIRMMKDIR FOF_NOERRORUI
 FOF_NOCOPYSECURITYATTRIBS FOF_MULTIDESTFILES FOF_CREATEPROGRESSDLG
);


my @OFN_flags = qw(
      OFN_READONLY OFN_OVERWRITEPROMPT OFN_HIDEREADONLY OFN_NOCHANGEDIR OFN_SHOWHELP
      OFN_ENABLEHOOK OFN_ENABLETEMPLATE OFN_ENABLETEMPLATEHANDLE OFN_NOVALIDATE
      OFN_ALLOWMULTISELECT OFN_EXTENSIONDIFFERENT OFN_PATHMUSTEXIST OFN_FILEMUSTEXIST
      OFN_CREATEPROMPT OFN_SHAREAWARE OFN_NOREADONLYRETURN OFN_NOTESTFILECREATE
      OFN_NONETWORKBUTTON OFN_NOLONGNAMES OFN_EXPLORER OFN_NODEREFERENCELINKS
      OFN_LONGNAMES OFN_SHAREFALLTHROUGH OFN_SHARENOWARN OFN_SHAREWARN
);

my @BIF_flags = qw(
     BIF_RETURNONLYFSDIRS BIF_DONTGOBELOWDOMAIN BIF_STATUSTEXT BIF_RETURNFSANCESTORS
     BIF_BROWSEFORCOMPUTER BIF_BROWSEFORPRINTER BIF_BROWSEINCLUDEFILES 
);

my @CSIDL_flags = qw(
     CSIDL_DESKTOP CSIDL_PROGRAMS CSIDL_CONTROLS CSIDL_PRINTERS CSIDL_PERSONAL
     CSIDL_FAVORITES CSIDL_STARTUP CSIDL_RECENT CSIDL_SENDTO CSIDL_BITBUCKET
     CSIDL_STARTMENU CSIDL_DESKTOPDIRECTORY CSIDL_DRIVES CSIDL_NETWORK CSIDL_NETHOOD
     CSIDL_FONTS CSIDL_TEMPLATES CSIDL_COMMON_STARTMENU CSIDL_COMMON_PROGRAMS
     CSIDL_COMMON_STARTUP CSIDL_COMMON_DESKTOPDIRECTORY CSIDL_APPDATA CSIDL_PRINTHOOD
);

@Win32::FileOp::EXPORT = (
 qw(  Recycle RecycleConfirm RecycleConfirmEach RecycleEx
      Delete DeleteConfirm DeleteConfirmEach DeleteEx
      Copy CopyConfirm CopyConfirmEach CopyEx
      Move MoveConfirm MoveConfirmEach MoveEx
      MoveAtReboot DeleteAtReboot MoveFile MoveFileEx CopyFile
      FillInDir UpdateDir
      FindInPATH FindInPath Relative2Absolute RelativeToAbsolute
      AddToRecentDocs EmptyRecentDocs
	  ReadINISectionKeys ReadINISections
      WriteToINI WriteToWININI ReadINI ReadWININI DeleteFromINI DeleteFromWININI
      OpenDialog SaveAsDialog BrowseForFolder
      recycle
      DesktopHandle GetDesktopHandle WindowHandle GetWindowHandle
      Compress Uncompress UnCompress Compressed SetCompression GetCompression CompressDir UncompressDir UnCompressDir
      Map Unmap Disconnect Mapped
 ),
 @FOF_flags,
 @OFN_flags,
 @BIF_flags,
 @CSIDL_flags,
);
#     FOF_CONFIRMMOUSE FOF_WANTMAPPINGHANDLE

@Win32::FileOp::EXPORT_OK = qw(FindInPATH FindInPath Relative2Absolute RelativeToAbsolute Map Unmap Disconnect Mapped);

%Win32::FileOp::EXPORT_TAGS = (
    INI => [qw( ReadINISectionKeys ReadINISections WriteToINI WriteToWININI ReadINI ReadWININI DeleteFromINI DeleteFromWININI )],
    DIALOGS => [qw( OpenDialog SaveAsDialog BrowseForFolder),
               @OFN_flags, @BIF_flags, @CSIDL_flags],
    _DIALOGS => [@OFN_flags, @BIF_flags, @CSIDL_flags],
    HANDLES => [qw( DesktopHandle GetDesktopHandle WindowHandle GetWindowHandle )],
    BASIC => [qw(
               Delete DeleteConfirm DeleteConfirmEach DeleteEx
               Copy CopyConfirm CopyConfirmEach CopyEx
               Move MoveConfirm MoveConfirmEach MoveEx
               MoveAtReboot DeleteAtReboot MoveFile MoveFileEx CopyFile
             ),
             @FOF_flags],
    _BASIC => [@FOF_flags],
    RECENT => [qw(AddToRecentDocs EmptyRecentDocs)],
    DIRECTORY => [qw(UpdateDir FillInDir)],
    COMPRESS => [qw(Compress Uncompress UnCompress Compressed SetCompression GetCompression CompressDir UncompressDir UnCompressDir)],
    MAP => [qw(Map Unmap Disconnect Mapped)],
);


use vars qw($ReadOnly $DesktopHandle $fileop $ProgressTitle);
$Win32::FileOp::DesktopHandle = 0;
$Win32::FileOp::WindowHandle = 0;
sub Win32::FileOp::GetDesktopHandle;
sub Win32::FileOp::GetWindowHandle;
$Win32::FileOp::fileop = 0;
$Win32::FileOp::ProgressTitle = '';

sub FO_MOVE     () { 0x01 }
sub FO_COPY     () { 0x02 }
sub FO_DELETE   () { 0x03 }
sub FO_RENAME   () { 0x04 }

sub FOF_CREATEPROGRESSDLG     () { 0x0000 } # default
sub FOF_MULTIDESTFILES        () { 0x0001 } # more than one dest for files
#sub FOF_CONFIRMMOUSE         () { 0x0002 } # not implemented
sub FOF_SILENT                () { 0x0004 } # don't create progress/report
sub FOF_RENAMEONCOLLISION     () { 0x0008 } # rename if coliding
sub FOF_NOCONFIRMATION        () { 0x0010 } # Don't prompt the user.
#sub FOF_WANTMAPPINGHANDLE    () { 0x0020 } # Fill in FILEOPSTRUCT.hNameMappings
sub FOF_ALLOWUNDO             () { 0x0040 } # recycle bin instead of delete
sub FOF_FILESONLY             () { 0x0080 } # on *.*, do only files
sub FOF_SIMPLEPROGRESS        () { 0x0100 } # means don't show names of files
sub FOF_NOCONFIRMMKDIR        () { 0x0200 } # don't confirm making needed dirs
sub FOF_NOERRORUI             () { 0x0400 } # don't put up error UI
sub FOF_NOCOPYSECURITYATTRIBS () { 0x0800 } # dont copy file Security Attributes

sub MOVEFILE_REPLACE_EXISTING   () { 0x00000001 }
sub MOVEFILE_COPY_ALLOWED       () { 0x00000002 }
sub MOVEFILE_DELAY_UNTIL_REBOOT () { 0x00000004 }

sub OFN_READONLY              () { 0x00000001}
sub OFN_OVERWRITEPROMPT       () { 0x00000002}
sub OFN_HIDEREADONLY          () { 0x00000004}
sub OFN_NOCHANGEDIR           () { 0x00000008}
sub OFN_SHOWHELP              () { 0x00000010}
sub OFN_ENABLEHOOK            () { #0x00000020;
    carp "OFN_ENABLEHOOK not implemented" }
sub OFN_ENABLETEMPLATE        () { #0x00000040;
    carp "OFN_ENABLEHOOK not implemented" }
sub OFN_ENABLETEMPLATEHANDLE  () { #0x00000080;
    carp "OFN_ENABLEHOOK not implemented" }
sub OFN_NOVALIDATE            () { 0x00000100}
sub OFN_ALLOWMULTISELECT      () { 0x00000200}
sub OFN_EXTENSIONDIFFERENT    () { 0x00000400}
sub OFN_PATHMUSTEXIST         () { 0x00000800}
sub OFN_FILEMUSTEXIST         () { 0x00001000}
sub OFN_CREATEPROMPT          () { 0x00002000}
sub OFN_SHAREAWARE            () { 0x00004000}
sub OFN_NOREADONLYRETURN      () { 0x00008000}
sub OFN_NOTESTFILECREATE      () { 0x00010000}
sub OFN_NONETWORKBUTTON       () { 0x00020000}
sub OFN_NOLONGNAMES           () { 0x00040000} # // force no long names for 4.x modules
                                               #if(WINVER >() { 0x0400)
sub OFN_EXPLORER              () { 0x00080000} # // new look commdlg
sub OFN_NODEREFERENCELINKS    () { 0x00100000}
sub OFN_LONGNAMES             () { 0x00200000} # // force long names for 3.x modules

sub OFN_SHAREFALLTHROUGH  () { 2}
sub OFN_SHARENOWARN       () { 1}
sub OFN_SHAREWARN         () { 0}


sub BIF_RETURNONLYFSDIRS   () { 0x0001 } #// For finding a folder to start document searching
sub BIF_DONTGOBELOWDOMAIN  () { 0x0002 } #// For starting the Find Computer
sub BIF_STATUSTEXT         () { 0x0004 } # Includes a status area in the dialog box.
      # The callback function can set the status text
      # by sending messages to the dialog box.
sub BIF_RETURNFSANCESTORS  () { 0x0008 }
sub BIF_BROWSEFORCOMPUTER  () { 0x1000 } #// Browsing for Computers.
sub BIF_BROWSEFORPRINTER   () { 0x2000 } #// Browsing for Printers
sub BIF_BROWSEINCLUDEFILES () { 0x4000 } #// Browsing for Everything

#BIF_BROWSEFORCOMPUTER	Only returns computers. If the user selects
#anything other than a computer, the OK button is grayed.

#BIF_BROWSEFORPRINTER	Only returns printers. If the user selects
#anything other than a printer, the OK button is grayed.

#BIF_DONTGOBELOWDOMAIN	Does not include network folders below the
#domain level in the tree view control.

#BIF_RETURNFSANCESTORS	Only returns file system ancestors. If the user
#selects anything other than a file system ancestor, the OK button is
#grayed.
 
#BIF_RETURNONLYFSDIRS	Only returns file system directories. If the
#user selects folders that are not part of the file system, the OK button
#is grayed.

#BIF_STATUSTEXT	Includes a status area in the dialog box. The callback
#function can set the status text by sending messages to the dialog box.

sub CSIDL_DESKTOP                   () { 0x0000 }
sub CSIDL_PROGRAMS                  () { 0x0002 }
sub CSIDL_CONTROLS                  () { 0x0003 }
sub CSIDL_PRINTERS                  () { 0x0004 }
sub CSIDL_PERSONAL                  () { 0x0005 }
sub CSIDL_FAVORITES                 () { 0x0006 }
sub CSIDL_STARTUP                   () { 0x0007 }
sub CSIDL_RECENT                    () { 0x0008 }
sub CSIDL_SENDTO                    () { 0x0009 }
sub CSIDL_BITBUCKET                 () { 0x000a }
sub CSIDL_STARTMENU                 () { 0x000b }
sub CSIDL_DESKTOPDIRECTORY          () { 0x0010 }
sub CSIDL_DRIVES                    () { 0x0011 }
sub CSIDL_NETWORK                   () { 0x0012 }
sub CSIDL_NETHOOD                   () { 0x0013 }
sub CSIDL_FONTS                     () { 0x0014 }
sub CSIDL_TEMPLATES                 () { 0x0015 }
sub CSIDL_COMMON_STARTMENU          () { 0x0016 }
sub CSIDL_COMMON_PROGRAMS           () { 0x0017 }
sub CSIDL_COMMON_STARTUP            () { 0x0018 }
sub CSIDL_COMMON_DESKTOPDIRECTORY   () { 0x0019 }
sub CSIDL_APPDATA                   () { 0x001a }
sub CSIDL_PRINTHOOD                 () { 0x001b }

#=rem
#sub FILE_SHARE_READ                 () { 0x00000001  }
#sub FILE_SHARE_WRITE                () { 0x00000002  }
#sub FILE_SHARE_DELETE               () { 0x00000004  }
#
#sub FILE_FLAG_WRITE_THROUGH         () { 0x80000000 }
#sub FILE_FLAG_OVERLAPPED            () { 0x40000000 }
#sub FILE_FLAG_NO_BUFFERING          () { 0x20000000 }
#sub FILE_FLAG_RANDOM_ACCESS         () { 0x10000000 }
#sub FILE_FLAG_SEQUENTIAL_SCAN       () { 0x08000000 }
#sub FILE_FLAG_DELETE_ON_CLOSE       () { 0x04000000 }
#sub FILE_FLAG_BACKUP_SEMANTICS      () { 0x02000000 }
#sub FILE_FLAG_POSIX_SEMANTICS       () { 0x01000000 }
#
#
#sub CREATE_NEW          () { 1 }
#sub CREATE_ALWAYS       () { 2 }
#sub OPEN_EXISTING       () { 3 }
#sub OPEN_ALWAYS         () { 4 }
#sub TRUNCATE_EXISTING   () { 5 }
#=cut

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

tie $Win32::FileOp::fileop, 'Lazy', sub {
  new Win32::API("shell32", "SHFileOperation", ['P'], 'I')
  or
  die "new Win32::API::SHFileOperation: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::copyfile, 'Lazy', sub {
  new Win32::API("KERNEL32", "CopyFile", [qw(P P I)], 'I')
  or
  die "new Win32::API::CopyFile: $!\n";
}, &LAZY_READONLY;

tie $Win32::FileOp::movefileexDel, 'Lazy', sub {
    new Win32::API("KERNEL32", "MoveFileEx", ['P','L','N'], 'I')
    or
    die "new Win32::API::MoveFileEx for delete: $!\n";
}, &LAZY_READONLY;

tie $Win32::FileOp::movefileex, 'Lazy', sub {
    new Win32::API("KERNEL32", "MoveFileEx", ['P','P','N'], 'I')
    or
    die "new Win32::API::MoveFileEx: $!\n";
}, &LAZY_READONLY;

tie $Win32::FileOp::SHAddToRecentDocs, 'Lazy', sub {
    new Win32::API("shell32", "SHAddToRecentDocs", ['I','P'], 'I')
    or
    die "new Win32::API::SHAddToRecentDocs: $!\n";
}, &LAZY_READONLY;

tie $Win32::FileOp::SHAddToRecentDocs, 'Lazy', sub {
    new Win32::API("shell32", "SHAddToRecentDocs", ['I','P'], 'I')
    or
    die "new Win32::API::SHAddToRecentDocs: $!\n";
}, &LAZY_READONLY;

tie $Win32::FileOp::writeINI, 'Lazy', sub {
    new Win32::API("KERNEL32", "WritePrivateProfileString", [qw(P P P P)], 'I')
    or
    die "new Win32::API::WritePrivateProfileString: $!\n"
}, &LAZY_READONLY;


tie $Win32::FileOp::writeWININI, 'Lazy', sub {
    new Win32::API("KERNEL32", "WriteProfileString", [qw(P P P)], 'I')
    or
    die "new Win32::API::WriteProfileString: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::deleteINI, 'Lazy', sub {
    new Win32::API("KERNEL32", "WritePrivateProfileString", [qw(P P L P)], 'I')
    or
    die "new Win32::API::WritePrivateProfileString for delete: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::deleteWININI, 'Lazy', sub {
    new Win32::API("KERNEL32", "WriteProfileString", [qw(P P L)], 'I')
    or
    die "new Win32::API::WriteProfileString for delete: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::readINI, 'Lazy', sub {
    new Win32::API("KERNEL32", "GetPrivateProfileString", [qw(P P P P N P)], 'N')
    or
    die "new Win32::API::GetPrivateProfileString: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::readWININI, 'Lazy', sub {
    new Win32::API("KERNEL32", "GetProfileString", [qw(P P P P N)], 'N')
    or
    die "new Win32::API::GetProfileString: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::GetOpenFileName, 'Lazy', sub {
    new Win32::API("comdlg32", "GetOpenFileName", ['P'], 'N')
    or
    die "new Win32::API::GetOpenFileName: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::GetSaveFileName, 'Lazy', sub {
    new Win32::API("comdlg32", "GetSaveFileName", ['P'], 'N')
    or
    die "new Win32::API::GetSaveFileName: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::CommDlgExtendedError, 'Lazy', sub {
    new Win32::API("comdlg32", "CommDlgExtendedError", [], 'N')
    or
    die "new Win32::API::CommDlgExtendedError: $!\n"
}, &LAZY_READONLY;


tie $Win32::FileOp::CreateFile, 'Lazy', sub {
    new Win32::API( "kernel32", "CreateFile", [qw(P N N P N N P)], 'N')
    or
    die "new Win32::API::DeviceIoControl: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::CloseHandle, 'Lazy', sub {
    new Win32::API( "kernel32", "CloseHandle", ['N'], 'N')
    or
    die "new Win32::API::CloseHandle: $!\n"
};

tie $Win32::FileOp::DeviceIoControl, 'Lazy', sub {
    new Win32::API( "kernel32", "DeviceIoControl", ['N', 'N', 'P', 'N', 'P', 'N', 'P', 'P'], 'N')
    or
    die "new Win32::API::DeviceIoControl: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::SHBrowseForFolder, 'Lazy', sub {
   new Win32::API("shell32", "SHBrowseForFolder", ['P'], 'N')
   or
   die "new Win32::API::SHBrowseForFolder: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::SHGetPathFromIDList, 'Lazy', sub {
   new Win32::API("shell32", "SHGetPathFromIDList", ['N','P'], 'I')
   or
   die "new Win32::API::SHGetPathFromIDList: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::SHGetSpecialFolderLocation, 'Lazy', sub {
   new Win32::API("shell32", "SHGetSpecialFolderLocation", ['N','I','P'], 'I')
   or
   die "new Win32::API::SHGetSpecialFolderLocation: $!\n"
}, &LAZY_READONLY;


tie $Win32::FileOp::GetFileVersionInfoSize, 'Lazy', sub {
   new Win32::API( "version", "GetFileVersionInfoSize", ['P', 'P'], 'N')
   or
   die "new Win32::API::GetFileVersionInfoSize: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::GetFileVersionInfo, 'Lazy', sub {
   new Win32::API( "version", "GetFileVersionInfo", ['P', 'N', 'N', 'P'], 'N')
   or
   die "new Win32::API::GetFileVersionInfo: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::VerQueryValue, 'Lazy', sub {
   new Win32::API( "version", "VerQueryValue", ['P', 'P', 'P', 'P'], 'N')
   or
   die "new Win32::API::VerQueryValue: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::WNetAddConnection3, 'Lazy', sub {
  new Win32::API("mpr.dll", "WNetAddConnection3", ['L','P','P','P','L'], 'L')
  or
  die "new Win32::API::WNetAddConnection3: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::WNetGetConnection, 'Lazy', sub {
  new Win32::API("mpr.dll", "WNetGetConnection", ['P','P','P'], 'L')
  or
  die "new Win32::API::WNetGetConnection: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::WNetCancelConnection2, 'Lazy', sub {
  new Win32::API("mpr.dll", "WNetCancelConnection2", ['P','L','I'], 'L')
  or
  die "new Win32::API::WNetCancelConnection2: $!\n"
}, &LAZY_READONLY;

tie $Win32::FileOp::GetLogicalDrives, 'Lazy', sub {
  new Win32::API("kernel32.dll", "GetLogicalDrives", [], 'N')
  or
  die "new Win32::API::GetLogicalDrives: $!\n"
}, &LAZY_READONLY;

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub Recycle {
    &DeleteEx (@_, FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT |
      FOF_NOERRORUI);
}

sub RecycleConfirm { &DeleteEx (@_, FOF_ALLOWUNDO); }

sub RecycleEx { my $opt = pop; $opt |= FOF_ALLOWUNDO; &DeleteEx (@_, $opt); }

sub Delete {
    &DeleteEx (@_, FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI);
}

sub DeleteConfirm { &DeleteEx (@_, FOF_CREATEPROGRESSDLG); }

sub DeleteEx {
    undef $Win32::FileOp::Error;
    my $options = pop;
    my ($opstruct, $filename);
    my @files = grep {-e $_} @_; # since we change the names, make a copy of the list

    # pass all files at once, join them by \0 and end by \0\0

    # fix to full paths

    @files = map {
        Relative2Absolute $_;
        $_;
    } @files;

    return undef unless @files;

    $filename = join "\0", @files;
    $filename .= "\0\0";        # double term the filename

    # pack fileop structure (really more like lLppIilP)
    # sizeof args = l4, L4, p4, p4, I4, i4, l4, P4 = 32 bytes

    if ($Win32::FileOp::ProgressTitle and $options & FOF_SIMPLEPROGRESS) {

        $Win32::FileOp::ProgressTitle .= "\0" unless $Win32::FileOp::ProgressTitle =~ /\0$/;
        $opstruct = pack ('LLpLILC2p', Win32::FileOp::GetWindowHandle, FO_DELETE,
                            $filename, 0, $options, 0, 0,0, $Win32::FileOp::ProgressTitle);

    } else {

        $opstruct = pack ('LLpLILLL', Win32::FileOp::GetWindowHandle, FO_DELETE,
                            $filename, 0, $options, 0, 0, 0);
    }
    # call delete SHFileOperation with structure

    unless ($Win32::FileOp::fileop->Call($opstruct)) {
        return 1;
    } else {
        $! = Win32::GetLastError();
        return undef;
    }
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub RecycleConfirmEach { &_DeleteConfirmEach (@_, FOF_ALLOWUNDO); }

sub DeleteConfirmEach  { &_DeleteConfirmEach (@_, FOF_CREATEPROGRESSDLG); }

sub _DeleteConfirmEach {
    undef $Win32::FileOp::Error;
    my $options =  pop;

    return undef unless @_;

    my $res = 0;
    my ($filename,$opstruct);
    while ($filename = shift) {

        Relative2Absolute $filename;
        $filename .= "\0\0";        # double term the filename
        my $was = -e $filename;

        if ($Win32::FileOp::ProgressTitle and $options & FOF_SIMPLEPROGRESS) {

            $Win32::FileOp::ProgressTitle .= "\0" unless $Win32::FileOp::ProgressTitle =~ /\0$/;
            $opstruct = pack ('LLpLILC2p', Win32::FileOp::GetWindowHandle, FO_DELETE,
                                $filename, 0, $options, 0, 0,0, $Win32::FileOp::ProgressTitle);

        } else {

            $opstruct = pack ('LLpLILLL', Win32::FileOp::GetWindowHandle, FO_DELETE,
                                $filename, 0, $options, 0, 0, 0);
        }

        # call delete SHFileOperation with structure

        unless ($Win32::FileOp::fileop->Call($opstruct)) {
            $res++ if ($was and !-e $filename);
        } else {
            $! = Win32::GetLastError();
        }
    }
    $res;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub Copy {
    &_MoveOrCopyEx (@_, FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR |
    FOF_SILENT # | FOF_NOERRORUI
      , FO_COPY);
}

sub CopyConfirm { &_MoveOrCopyEx (@_, FOF_CREATEPROGRESSDLG, FO_COPY); }

*CopyConfirmEach = \&CopyConfirm;

sub CopyEx { &_MoveOrCopyEx (@_, FO_COPY); }

sub Move   {
    &_MoveOrCopyEx (@_, FOF_NOCONFIRMATION | FOF_NOCONFIRMMKDIR | FOF_SILENT # | FOF_NOERRORUI
      , FO_MOVE);
}

sub MoveConfirm { &_MoveOrCopyEx (@_, FOF_CREATEPROGRESSDLG, FO_MOVE); }

*MoveConfirmEach = \&MoveConfirm;

sub MoveEx { &_MoveOrCopyEx (@_, FO_MOVE); }

sub _MoveOrCopyEx {
    undef $Win32::FileOp::Error;
    my $func = pop;
    my $options = pop;
    my ($opstruct, $filename, $hash, $res, $from, $to);

    if (@_ % 2) { die "Wrong number of arguments to Win32::FileOp::CopyEx!\n" };

    my $i = 0;
    while (defined ($from = $_[$i++]) and defined ($to = $_[$i++])) {

    # fix to full paths

        if (ref $from eq 'ARRAY') {

            my @files = map {
                my $s = $_;
                Relative2Absolute $s;
                $s;
            } @$from;
            $from = join "\0", @files;

        } else {

            Relative2Absolute $from;
            $from =~ s#/#\\#g;

            # if to ends in slash, get filename from from

            if ($to =~ m{[\\/]$} and $to !~ /^\w:\\$/) {
                my $tmp = $from;
                $tmp =~ s#^.*[\\/](.*?)$#$1#;
                $to .= $tmp;
            }
            $to .= '\\' if $to =~ /:$/;
        }
        $from .= "\0\0";        # double term the filename

        my $options = $options;
        if (ref $to eq 'ARRAY') {
            my $strto='';
            foreach (@$to) {
                $strto .= RelativeToAbsolute($_) . "\0";
            }
            $to = $strto;
            $options |= FOF_MULTIDESTFILES;
        } else {
            Relative2Absolute($to);
        }
        $to .= "\0\0";        # double term the filename
        $to =~ s#/#\\#g;

        if ($Win32::FileOp::ProgressTitle and $options & FOF_SIMPLEPROGRESS) {

            $Win32::FileOp::ProgressTitle .= "\0" unless $Win32::FileOp::ProgressTitle =~ /\0$/;
            $opstruct = pack ('LLppILC2p', Win32::FileOp::GetWindowHandle, $func,
              $from, $to, $options, 0, 0,0, $Win32::FileOp::ProgressTitle);

        } else {

            $opstruct = pack ('LLppILLL', Win32::FileOp::GetWindowHandle, $func,
              $from, $to, $options, 0, 0, 0);

        }

        unless ($Win32::FileOp::fileop->Call($opstruct)) {
            $res++;
        } else {
            $! = Win32::GetLastError();
            return undef;
        }
    }
    $res;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub MoveFile {
    MoveFileEx(@_,MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED);
}

sub MoveAtReboot {
    if (Win32::IsWinNT) {
        MoveFileEx(@_,MOVEFILE_REPLACE_EXISTING | MOVEFILE_DELAY_UNTIL_REBOOT);
    } else {
        undef $Win32::FileOp::Error;
        my @a;
        my $i=0;
        while ($_[$i]) {
            $a[$i+1]= Win32::GetShortPathName $_[$i];
            ($a[$i]= $_[$i+1]) =~ s#^(.*)([/\\].*?)$#Win32::GetShortPathName($1).$2#e;
            $i+=2;
        }
        Relative2Absolute(@a);
        WriteToINI($ENV{WINDIR}.'\\wininit.ini','Rename',@a);
    }
}

sub CopyFile {
    undef $Win32::FileOp::Error;
    my ($from,$to);

    while ($from = shift and $to = shift) {
#        Relative2Absolute($to,$from);
        $to .= "\0";
        $from .= "\0";
        $Win32::FileOp::copyfile->Call($from,$to, 0);
    }
}


sub DeleteAtReboot {
    undef $Win32::FileOp::Error;
    if (Win32::IsWinNT)  {
        my $file;
        while ($file = shift) {
            Relative2Absolute($file);
            $Win32::FileOp::movefileexDel->Call($file, 0, MOVEFILE_DELAY_UNTIL_REBOOT);
        }
    } else {
        my @a;
        foreach (@_) {
            my $tmp=$_;
            Relative2Absolute($tmp);
            $tmp = Win32::GetShortPathName $tmp;
            push @a, 'NUL', $tmp;
        }
        WriteToINI($ENV{WINDIR}.'\\wininit.ini','Rename',@a);
    }
    1;
}

sub MoveFileEx {
    undef $Win32::FileOp::Error;
    my $options = pop;

    my ($from,$to);
    while ($from = shift and $to = shift) {
        Relative2Absolute($to,$from);
        $to .= "\0";
        $from .= "\0";
        $Win32::FileOp::movefileex->Call($from,$to, $options);
    }
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub UpdateDir {
 undef $Win32::FileOp::Error;
 local ($Win32::FileOp::from,$Win32::FileOp::to,$Win32::FileOp::callback) = @_;
 -d $Win32::FileOp::from or return undef;
 -d $Win32::FileOp::to or File::Path::mkpath $Win32::FileOp::to, 0777 or return undef;
 Relative2Absolute($Win32::FileOp::to);
 my $olddir = cwd;
 chdir $Win32::FileOp::from;
 find(\&_UpdateDir, '.');
 chdir $olddir;
}

sub _UpdateDir {
  undef $Win32::FileOp::Error;
  my $fullto = "$Win32::FileOp::to\\$File::Find::dir\\$_";
  $fullto =~ s#/#\\#g;
  $fullto =~ s#\\\.\\#\\#;
  if (-d $_) {
    return if /^\.\.?$/ or -d $fullto;
    mkdir $fullto, 0777;
  } else {
    my $age = -M($fullto);
    if (! -e($fullto) or $age > -M($_)) {
      if (! defined $Win32::FileOp::callback or &$Win32::FileOp::callback()) {
        CopyFile $_, $fullto;
      }
    }
  }
}


sub FillInDir {
 undef $Win32::FileOp::Error;
 local ($Win32::FileOp::from,$Win32::FileOp::to,$Win32::FileOp::callback) = @_;
 -d $Win32::FileOp::from or return undef;
 -d $Win32::FileOp::to or File::Path::mkpath $Win32::FileOp::to, 0777 or return undef;
 Relative2Absolute($Win32::FileOp::to);
 my $olddir = cwd;
 chdir $Win32::FileOp::from;
 find(\&_FillInDir, '.');
 chdir $olddir;
}

sub _FillInDir {
  my $fullto = "$Win32::FileOp::to\\$File::Find::dir\\$_";
  $fullto =~ s#/#\\#g;
  $fullto =~ s#\\\.\\#\\#;
  if (-d $_) {
    return if /^\.\.?$/ or -d $fullto;
    mkdir $fullto, 0777;
  } else {
    if (! -e($fullto)) {
      if (! defined $Win32::FileOp::callback or &$Win32::FileOp::callback()) {
        CopyFile $_, $fullto;
      }
    }
  }
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub AddToRecentDocs {
 undef $Win32::FileOp::Error;

 my $file;
 my $res=0;
 while ($file = shift) {
  next unless -e $file;
  Relative2Absolute($file);
  $file .= "\0";
  $Win32::FileOp::SHAddToRecentDocs->Call(2,$file);
  $res++;
 }
 $res;
}

sub EmptyRecentDocs {
 undef $Win32::FileOp::Error;
 my $x = 0;
 $Win32::FileOp::SHAddToRecentDocs->Call(2,$x);
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub WriteToINI {
    undef $Win32::FileOp::Error;
    my $INI = shift;$INI .= "\0";
    my $section = shift;$section .= "\0";
    my ($name,$value);
    while ($name = shift and $value = shift) {
        $name .= "\0";$value .= "\0";
        $Win32::FileOp::writeINI->Call($section,$name,$value,$INI)
        or return undef;
    }
    1;
}

sub WriteToWININI {
    undef $Win32::FileOp::Error;
    my $section = shift;$section .= "\0";
    my ($name,$value);
    while ($name = shift and $value = shift) {
        $name .= "\0";$value .= "\0";
        $Win32::FileOp::writeWININI->Call($section,$name,$value)
        or return undef;
    }
    1;
}

sub DeleteFromINI {
    undef $Win32::FileOp::Error;
    my $INI = shift;$INI .= "\0";
    my $section = shift;$section .= "\0";
    my $name;
    while ($name = shift) {
        $name .= "\0";
        $Win32::FileOp::deleteINI->Call($section,$name,0,$INI)
        or return undef;
    }
    1;
}

sub DeleteFromWININI {
    undef $Win32::FileOp::Error;
    my $section = shift;$section .= "\0";
    my $name;
    while ($name = shift) {
        $name .= "\0";
        $Win32::FileOp::deleteWININI->Call($section,$name,0)
        or return undef;
    }
    1;
}

sub ReadINI {
    undef $Win32::FileOp::Error;
    my $INI = shift;$INI .= "\0";
    my $section = shift;$section .= "\0";
    my $name = shift;$name .= "\0";
    my $default = shift;$default .= "\0";
    my $value = _ReadINI($section,$name,$default,$INI);

    $value =~ s/\0.*$// or return;
    return $value;
}

# MTY hack : Michael Yamada <myamada@gj.com>
sub ReadINISectionKeys {
    undef $Win32::FileOp::Error;
    my $INI = shift;$INI='win.ini' unless $INI;$INI .= "\0";
    my $section = shift;$section .= "\0";
	my $name = 0; # pass null to API
	my $default = "\0";
	my @values;

	@values = split(/\0/,_ReadINI($section,$name,$default,$INI));
	@{$_[0]} = @values if (ref $_[0] eq 'ARRAY');
	return wantarray() ? @values : (@values ? \@values : undef);
}
# END MTY Hack

sub ReadINISections {
    undef $Win32::FileOp::Error;
    my $INI = shift;$INI='win.ini' unless $INI;$INI .= "\0";
    my $section = 0; # pass null to API
	my $name = 0; 
	my $default = "\0";
	my @values;

	@values = split(/\0/,_ReadINI($section,$name,$default,$INI));
	@{$_[0]} = @values if (ref $_[0] eq 'ARRAY');
	return wantarray() ? @values : (@values ? \@values : undef);
}


sub ReadWININI {
    undef $Win32::FileOp::Error;
    my $section = shift;$section .= "\0";
    my $name = shift;$name .= "\0";
    my $default = shift;$default .= "\0";
    my $value = "\0" x 2048;

    $Win32::FileOp::readWININI->Call($section,$name,$default,$value,256)
    or return undef;

    $value =~ s/\0.*$// or return;
    return $value;
}

sub _ReadINI { # $section, $name, $default, $INI
	my $size = 10;#24;
    my $value = "\0" x $size; # large buffer to accomodate many keys
    my $retsize = $size-2;
    while ($size-$retsize <=2) {
     $size*=2;$value = "\0" x $size;
     $retsize = $Win32::FileOp::readINI->Call($_[0],$_[1],$_[2],$value,$size,$_[3])
     or return '';
    }
    return $value;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub OpenDialog {
   OpenOrSaveDialog($Win32::FileOp::GetOpenFileName,@_);
}

sub SaveAsDialog {
   OpenOrSaveDialog($Win32::FileOp::GetSaveFileName,@_);
}

sub OpenOrSaveDialog {
    undef $Win32::FileOp::Error;
    my $fun = shift;
    my $params;
    if ((ref $_[0]) =~ /HASH/) {
        $params = $_[0];
        $params->{filename} = $_[1] if defined $_[1];
    } else {
        if (@_ % 2) {
            my $filename = pop;
            $params = {@_};
            $params->{filename} = $filename;
        } else {
            $params = {@_};
        }
    }

    $params->{handle} = 'self' unless exists $params->{handle};

    my $lpstrFilter = '';
    if ((ref $params->{filters}) =~ /HASH/) {
        foreach (keys %{$params->{filters}}) {
            $lpstrFilter .= $_ . "\0" . $params->{filters}->{$_} . "\0";
        }
    } elsif ((ref $params->{filters}) =~ /ARRAY/) {
        my ($title,$filter,$i);
        $i=0;$lpstrFilter='';
        while ($title = ${$params->{filters}}[$i++] and $filter = ${$params->{filters}}[$i++]) {
            $lpstrFilter .= $title . "\0" . $filter . "\0";
        }
        $params->{defaultfilter} = $title if $title && !$params->{defaultfilter};
    } elsif ($params->{filters}) {
        $lpstrFilter = $params->{filters};
        $lpstrFilter .= "\0\0" unless $lpstrFilter =~ /\0\0$/
    } else {
        $lpstrFilter = "\0\0";
    }

my $W = $^W;
$^W=0;

    my $nFilterIndex = $params->{defaultfilter};
    $nFilterIndex = 1 unless $nFilterIndex>0; # to be sure it's a reasonable number
    
    my $lpstrFile = $params->{filename}."\0".
    ($params->{options} & OFN_ALLOWMULTISELECT
     ? ' ' x ($Win32::FileOp::BufferSize - length $params->{filename})
     : ' ' x 256
    );

    my $lpstrFileTitle = "\0";
    my $lpstrInitialDir = $params->{dir} . "\0";
    my $lpstrTitle  = $params->{title} . "\0";
    my $Flags = $params->{options};
    my $lpstrDefExt = $params->{extension}."\0";
    my $lpTemplateName = "\0";
    my $Handle = $params->{handle};
    if ($Handle =~ /^self$/i) {$Handle = GetWindowHandle()};
    
$^W=$W;

    my $struct = pack "LLLpLLLpLpLppLIIpLLp",
     (
      76,                        #'lStructSize'       #  DWORD
      $Handle,                   #'hwndOwner'         #  HWND
      0,                         #'hInstance'         #  HINSTANCE
      $lpstrFilter,              #'lpstrFilter'       #  LPCTSTR
      0,
      0,
#     $lpstrCustomFilter,        #'lpstrCustomFilter' #  LPTSTR
#     length $lpstrCustomFilter, #'nMaxCustFilter'    #  DWORD
#I'm not able to make it work with CustomFilter

      $nFilterIndex,                         #'nFilterIndex'      #  DWORD
      $lpstrFile,                #'lpstrFile'         #  LPTSTR
      length $lpstrFile,         #'nMaxFile'          #  DWORD
      $lpstrFileTitle,           #'lpstrFileTitle'    #  LPTSTR
      length $lpstrFileTitle,    #'nMaxFileTitle'     #  DWORD
      $lpstrInitialDir,          #'lpstrInitialDir'   #  LPCTSTR
      $lpstrTitle,               #'lpstrTitle'        #  LPCTSTR
      $Flags,                    #'Flags'             #  DWORD
      0,                         #'nFileOffset'       #  WORD
      0,                         #'nFileExtension'    #  WORD
      $lpstrDefExt,              #'lpstrDefExt'       #  LPCTSTR
      0,                         #'lCustData'         #  DWORD
      0,                         #'lpfnHook'          #  LPOFNHOOKPROC
      $lpTemplateName            #'lpTemplateName'    #  LPCTSTR
     );

   if ($fun->Call($struct)) {
        $Flags = unpack("L", substr $struct, 52, 4);
        $Win32::FileOp::SelectedFilter = unpack("L", substr $struct, 6*4, 4);

        $Win32::FileOp::ReadOnly = ($Flags & OFN_READONLY);

        if ($Flags & OFN_ALLOWMULTISELECT) {
            $lpstrFile =~ s/\0\0.*$//;
            my @result;
            if ($Flags & OFN_EXPLORER) {
                @result = split "\0", $lpstrFile;
            } else {
                @result = split " ", $lpstrFile;
            }
            my $dir = shift @result;
            $dir =~ s/\\$//; # only happens in root
            return $dir unless @result;
            return map {$dir . '\\' . $_} @result;
        } else {
           $lpstrFile =~ s/\0.*$//;
           return $lpstrFile;
        }
#   } else {
#    my $err = $Win32::FileOp::Error = $Win32::FileOp::CommDlgExtendedError->Call();
#    if ($err == 12291)  {
#        print "Shit, the buffer was too small!\n";
#        $fun->Call($struct);
#    }
   }
   return;
}

#=======================

sub BrowseForFolder {
   undef $Win32::FileOp::Error;
   my ($hwndOwner, $pidlRoot, $pszDisplayName,
       $lpszTitle, $nFolder, $ulFlags,
       $lpfn, $lParam, $iImage, $pszPath)
      =
      (GetWindowHandle(), "\0"x260, " "x260,
       shift() || "\0", shift() || 0, (shift() || 0) | 0x0000,
       "\0", 0, 0, " "x260);

   $nFolder = CSIDL_DRIVES() unless defined $nFolder;

   $Win32::FileOp::SHGetSpecialFolderLocation->Call($hwndOwner, $nFolder, $pidlRoot)
   and return undef;
   $pidlRoot =~ s/\0.*$//s;
   $pidlRoot = hex unpack 'H*',(join'', reverse split//, $pidlRoot);

   my $browseinfo = pack 'LLppIaLI',
      ($hwndOwner, $pidlRoot, $pszDisplayName, $lpszTitle,
       $ulFlags, $lpfn, $lParam, $iImage);

   my $bool = $Win32::FileOp::SHGetPathFromIDList->Call(
               $Win32::FileOp::SHBrowseForFolder->Call($browseinfo),
               $pszPath
              );

   $pszPath =~ s/\0.*$//s;
   $bool ? $pszPath : undef;
}      

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub FindInPATH {
    undef $Win32::FileOp::Error;
    my $file = shift;
    return $file if -e $file;
    foreach (split ';',$ENV{PATH}) {
        return $_.'/'.$file if -e $_.'/'.$file;
    }
    return undef;
}
*FindInPath = \&FindInPATH;


#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub GetDesktopHandle {
    undef $Win32::FileOp::Error;
    my ($function, $handle);

# if handle already saved, use that one

    return $Win32::FileOp::DesktopHandle if $Win32::FileOp::DesktopHandle != 0;

# find GetDesktopWindow routine

$function = new Win32::API("user32", "GetDesktopWindow", ['V'], 'I') or
  die "new Win32::API::GetDesktopHandle: $!\n";

# call it, get window handle back, save it and return it

$Win32::FileOp::DesktopHandle = $function->Call();

}

sub GetWindowHandle {
    undef $Win32::FileOp::Error;
    if (! $Win32::FileOp::WindowHandle) {
        my $GetConsoleTitle = new Win32::API("kernel32", "GetConsoleTitle", ['P','N'],'N');
        my $SetConsoleTitle = new Win32::API("kernel32", "SetConsoleTitle", ['P'],'N');
        my $SleepEx = new Win32::API("kernel32", "Sleep", ['N','I'],'V');
        my $FindWindow = new Win32::API("user32", "FindWindow", ['P','P'],'N');

        my $oldtitle = " " x 1024;
        $GetConsoleTitle->Call($oldtitle, 1024);
        my $newtitle = sprintf("PERL-%d-%d", Win32::GetTickCount(), $$);
        $SetConsoleTitle->Call($newtitle);
        $SleepEx->Call(40,1);
        $Win32::FileOp::WindowHandle = $FindWindow->Call(0, $newtitle);
        $SetConsoleTitle->Call($oldtitle);
    }
    return $Win32::FileOp::WindowHandle;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub SetCompression {
    undef $Win32::FileOp::Error;
    my $file;
    my $flag;
    if ($_[-1] eq ($_[-1]+0)) {
        $flag = pop
    } else {
        $flag = 1;
    }
    $_[0] = $_ unless @_;
    while ($file = shift) {

#print "\t$file\n";

     my $handle;
     $handle = $Win32::FileOp::CreateFile->Call($file, 0xc0000000, 7, 0, 3, 0x2000000, 0);
#     $handle = $Win32::FileOp::CreateFile->Call($file, FILE_FLAG_WRITE_THROUGH | FILE_FLAG_OVERLAPPED,
#     FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, 0,
#     OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, 0);
     
     if($handle != -1) {
         my $br = pack("L", 0);
         my $inbuffer = pack("S", $flag);
         my $comp = $Win32::FileOp::DeviceIoControl->Call(
             $handle, 639040, $inbuffer, 2, 0, 0, $br, 0,
         );
         if(!$comp) {
             $Win32::FileOp::Error = "DeviceIoControl failed: "
                . Win32::FormatMessage(Win32::GetLastError);
             return undef;
         }
         $Win32::FileOp::CloseHandle->Call($handle);
         next;
     } else {
         $Win32::FileOp::Error = "CreateFile failed: "
            . Win32::FormatMessage(Win32::GetLastError);
         return undef;
     }
    }
    return 1;
}

sub GetCompression {
    undef $Win32::FileOp::Error;
    my ($file) = @_;
    $file = $_ unless defined $file;
    my $permission = hex('80000000') | hex('40000000');
    my $handle = $Win32::FileOp::CreateFile->Call($file, $permission, 0, 0, 3, 0, 0);
    if($handle != -1) {
        my $br = pack("L", 0);
        my $outbuffer = pack("S", 0);
        my $comp = $Win32::FileOp::DeviceIoControl->Call(
            $handle, 589884, 0, 0, $outbuffer, 2, $br, 0,
        );
        if(!$comp) {
            $Win32::FileOp::Error = "DeviceIoControl failed: "
               . Win32::FormatMessage(Win32::GetLastError);
            return undef;
        }
        $Win32::FileOp::CloseHandle->Call($handle);
        return unpack("S", $outbuffer);
    } else {
        $Win32::FileOp::Error = "CreateFile failed: ",
         Win32::FormatMessage(Win32::GetLastError);
        return undef;
    }
}

sub Compress {SetCompression(@_,1)}
sub Uncompress {SetCompression(@_,0)}
*UnCompress = \&Uncompress;
sub Compressed {&GetCompression}


sub UncompressDir {
    undef $Win32::FileOp::Error;
    if (ref $_[-1] eq 'CODE') {
        my $fun = pop;
        find( sub{Uncompress if &$fun}, @_);
    } else {
        find( sub {Uncompress}, @_);
    }
}
*UnCompressDir = \&UncompressDir;

sub CompressDir {
    undef $Win32::FileOp::Error;
    if (ref $_[-1] eq 'CODE') {
        my $fun = pop;
        find( sub{Compress if &$fun}, @_);
    } else {
        find( sub {Compress}, @_);
    }
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

sub FreeDriveLetters {
   undef $Win32::FileOp::Error;
   my (@dr, $i);

   my $bitmask = $Win32::FileOp::GetLogicalDrives->Call();
   for $i(0..25) {
     push (@dr, ('A'..'Z')[$i]) unless $bitmask & 2**$i;
   }
   @dr;
}


sub Map {
 undef $Win32::FileOp::Error;
 my $disk = $_[0] =~ m#^[\\/]# ? (FreeDriveLetters())[-1] : shift;
 my $type = ($disk =~ s/^(\w)(:)?$/$1:/) ? 1 : 2; $disk .= "\0";
 my $share = shift || croak('Ussage: Win32::FileOp::Map([$drive,]$share[,\%options])',"\n");
 $share .= "\0";
 my $opt = shift || {};
 croak 'Ussage: Win32::FileOp::Map([$drive,]$share[,\%options])',"\n"
  unless (ref $opt eq 'HASH');
 my $username = 0;
 if (defined $opt->{user}) {
  $username = $opt->{user}."\0";
  $username =~ s/(.)/\0$1/g if Win32::IsWinNT;
 }
 my $passwd = 0;
 if (defined $opt->{passwd}) {
  $passwd = $opt->{passwd}."\0";
  $passwd =~ s/(.)/\0$1/g if Win32::IsWinNT;
 }
 my $options = $opt->{persistent} ? 1 : 0;
 my $struct = pack('LLLLppLL',0,$type,0,0,$disk,$share,0,0);
 my $res;

 if ($res = $Win32::FileOp::WNetAddConnection3->Call(GetDesktopHandle(),$struct,$username,$passwd,$options)) {
    if ($res == 1202 and $opt->{overwrite}) {
        Unmap($disk);
        $Win32::FileOp::WNetAddConnection3->Call(GetDesktopHandle(),$struct,$username,$passwd,$options)
         and return;
    } else {
        return;
    }
 }
 $disk =~ s/^(\w:).*$/$1/;
 $disk;
}

sub Disconnect {
 undef $Win32::FileOp::Error;
 croak 'Ussage: Win32::FileOp::Map([$drive,]$share[,\%options])',"\n"
  unless @_;
 my $disk = shift() . "\0";$disk =~ s/^(\w)\0$/$1:\0/;
 my $opt = shift() || {};
 croak 'Ussage: Win32::FileOp::Map([$drive,]$share[,\%options])',"\n"
  unless (ref $opt eq 'HASH');
 my $options = $opt->{persistent} ? 1 : 0;
 my $force   = $opt->{force} ? 1 : 0;

 $Win32::FileOp::WNetCancelConnection2->Call($disk,$options,$force)
  and return;
 1;
}

sub Unmap {
    undef $Win32::FileOp::Error;
    if (ref $_[1] eq 'HASH') {
        $_[1]->{persistent} = 1 unless exists $_[1]->{persistent};
    } else {
        $_[1] = {persistent => 1}
    }
    goto &Disconnect;
}

sub Mapped {
 undef $Win32::FileOp::Error;
 goto &_MappedAll unless (@_);
 my $disk = shift();
 if ($disk =~ m#^[\\/][\\/]#) {
    $disk =~ s#/#\\#g;
    $disk = uc $disk;
    my %drives = _MappedAll();
    my ($drive,$share);
    while (($drive,$share) = each %drives) {
        return uc($drive).':' if (uc($share) eq $disk);
    }
    return;
 } else {
  $disk =~ s/^(\w)$/$1:/;$disk.="\0";
  my $size = 1024;
  my $share = "\0" x $size;

  $size = pack('L',$size);
  $Win32::FileOp::WNetGetConnection->Call($disk,$share,$size)
   and return;
  $share =~ s/\0.*$//;
  return $share;
 }
}

sub _MappedAll {
    my %hash;
    my $share;
    foreach (('A'..'Z')) {
        $share = Mapped $_
        and
        $hash{$_}=$share;
    }
    return %hash;
}

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

package Win32::FileOp::Error;
require Tie::Hash;
@Win32::FileOp::Error::ISA=qw(Tie::Hash);

sub TIEHASH {
    my $pkg = shift;
    my %hash = @_;
    my $self = \%hash;
    bless $self, $pkg;
}

sub FETCH { $_[0]->{$_[1]} || Win32::FormatMessage($_[1]) || "Unknown error ($_[1])" };

package Win32::FileOp;

tie %Win32::FileOp::ERRORS, 'Win32::FileOp::Error', (
 12291 => 'Shit, the buffer was too small!'
);

#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

1;

__END__

=head1 NAME

 Win32::FileOp - 0.10.3

=head1 DESCRIPTION

Module for file operations with fancy dialog boxes, for moving files
to recycle bin, reading and updating INI files and file operations in general.

Unless mentioned otherwise all functions work both under WinNT and Win95.

Version 0.10.3

=head2 Functions

C<GetDesktopHandle> C<GetWindowHandle>

C<Copy> C<CopyConfirm> C<CopyConfirmEach> C<CopyEx>

C<Move> C<MoveConfirm> C<MoveConfirmEach> C<MoveEx>

C<MoveFile> C<MoveFileEx> C<CopyFile> C<MoveAtReboot>

C<Recycle> C<RecycleConfirm> C<RecycleConfirmEach> C<RecycleEx>

C<Delete> C<DeleteConfirm> C<DeleteConfirmEach> C<DeleteEx> C<DeleteAtReboot>

C<UpdateDir> C<FillInDir>

C<Compress> C<Uncompress> C<Compressed> C<SetCompression> C<GetCompression>
C<CompressDir> C<UncompressDir>

C<AddToRecentDocs> C<EmptyRecentDocs>

C<WriteToINI> C<WriteToWININI> C<ReadINI> C<ReadWININI> 

C<DeleteFromINI> C<DeleteFromWININI>

C<OpenDialog> C<SaveAsDialog> C<BrowseForFolder>

C<Map> C<Unmap> C<Disconnect> C<Mapped>

=over 2

=item GetDesktopHandle

 use Win32::FileOp
 $handle = GetDesktopHandle()

Same as: $handle = $Win32::FileOp::DesktopHandle

Used to get desktop window handle when confirmation is used.
The value of the handle can be gotten from $Win32::FileOp::DesktopHandle.

Returns the Desktop Window handle.

=item GetWindowHandle

 use Win32::FileOp
 $handle = GetWindowHandle()

Same as: $handle = $Win32::FileOp::WindowHandle

Used to get the console window handle when confirmation is used.
The value of the handle can be gotten from $Win32::FileOp::WindowHandle.

Returns the Console Window handle.

=item Copy

 Copy ($FileName => $FileOrDirectoryName [, ...])
 Copy (\@FileNames => $DirectoryName [, ...] )
 Copy (\@FileNames => \@FileOrDirectoryNames [, ...])

Copies the specified files. Doesn't show any confirmation nor progress dialogs.

It may show an error message dialog, because I had to omit FOF_NOERRORUI
from its call to allow for autocreating directories.

You should end the directory names by backslash so that they are
not mistaken for filenames. It is not necessary if
the directory already exists or if you use Copy \@filenames => $dirname.

Returns true if successful.

Rem: Together with Delete, Move, DeleteConfirm, CopyConfirm,
MoveConfirm, CopyEx, MoveEx, DeleteEx and Recycle based on Win32 API function
SHFileOperation().

=item CopyConfirm

 CopyConfirm ($FileName => $FileOrDirectoryName [, ...])
 CopyConfirm (\@FileNames => $DirectoryName [, ...] )
 CopyConfirm (\@FileNames => \@FileOrDirectoryNames [, ...])

Copies the specified files. In case of a collision, shows a confirmation dialog.
Shows progress dialogs.

Returns true if successful.

=item CopyConfirmEach

The same as CopyConfirm.

=item CopyEx

 CopyEx ($FileName => $FileOrDirectoryName, [...], $options)
 CopyEx (\@FileNames => $DirectoryName, [...], $options)
 CopyEx (\@FileNames => \@FileOrDirectoryNames, [...], $options)

Copies the specified files. See below for the available options (C<FOF_> constants).

Returns true if successful.

=item Move

Moves the specified files. Parameters as C<Copy>

It may show an error message dialog, because I had to omit FOF_NOERRORUI
from its call to allow for autocreating directories.

=item MoveConfirm

Moves the specified files. Parameters as C<CopyConfirm>

=item MoveConfirmEach

The same as MoveConfirm

=item MoveEx

Moves the specified files. Parameters as C<CopyEx>

=item MoveAtReboot

 MoveAtReboot ($FileName => $DestFileName, [...])

This function moves the file during the next start of the system.

=item MoveFile

 MoveFile ($FileName => $DestFileName [, ...])

Move files. This function uses API function MoveFileEx as well
as MoveAtReboot. It may be a little quicker than C<Move>, but
it doesn't understand wildcards and the $DestFileName may not be a directory.

REM: Based on Win32 API function MoveFileEx().

=item MoveFileEx

 MoveFileEx ($FileName => $DestFileName [, ...], $options)

This is a simple wrapper around the API function MoveFileEx, it calls the function
for every pair of files with the $options you specify.
See below for the available options (C<FOF_>... constants).

REM: Based on Win32 API function MoveFileEx().

=item CopyFile

 CopyFile ($FileName => $DestFileName [, $FileName2 => $DestFileName2 [, ...]])

Copy a file somewhere. This function is not able to copy directories!

REM: Based on Win32 API function CopyFile().

=item Recycle

 Recycle @filenames

Send the files into the recycle bin. You will not get any confirmation dialogs.

Returns true if successful.

=item RecycleConfirm

 RecycleConfirm @filenames

Send the files into the recycle bin. You will get a confirmation dialog if you
have "Display delete confirmation dialog" turned on in your recycle bin. You
will confirm the deletion of all the files at once.

Returns true if successful. Please remember that this function is successful
even if the user chose [No] on the confirmation dialog!

=item RecycleConfirmEach

 RecycleConfirmEach @filenames

Send the files into the recycle bin. You will get a separate confirmation
dialog for each file if you have "Display delete confirmation dialog" turned
on in your recycle bin. You will confirm the deletion of all the files at once.

Returns the number of files that were successfully deleted.

=item RecycleEx

 RecycleEx @filenames, $options

Send the files into the recycle bin. You may specify the options for deleting,
see below.  You may get a confirmation dialog if you have "Display delete
confirmation dialog" turned on in your recycle bin, if so, you will confirm the
deletion of all the files at once.

Returns true if successful. Please remember that this function is successful
even if the user chose [No] on the confirmation dialog!

The $options may be constructed from C<FOF_>... constants.

=item Delete

 Delete @filenames

Deletes the files. You will not get any confirmation dialogs.

Returns true if successful.

=item DeleteConfirm

 DeleteConfirm @filenames

Deletes the the files. You will get a confirmation dialog to confirm
the deletion of all the files at once.

Returns true if successful. Please remember that this function is successful
even if the user selected [No] on the confirmation dialog!

=item DeleteConfirmEach

 DeleteConfirmEach @filenames

Deletes the files. You will get a separate confirmation dialog for each file.

Returns the number of files that were successfully deleted.

=item DeleteEx

 DeleteEx @filenames, $options

Deletes the files. You may specify the options for deleting,
see below.  You may get a confirmation dialog if you have "Display delete
confirmation dialog" turned on in your recycle bin.

Returns true if successful. Please remember that this function is successful
even if the user selected [No] on the confirmation dialog!

=item DeleteAtReboot

 DeleteAtReboot @files

This function moves the file during the next start of the system.

=item UpdateDir

 UpdateDir $SourceDirectory, $DestDirectory [, \&callback]

Copy the newer or updated files from $SourceDir to $DestDir. Processes subdirectories!
The &callback function is called for each file to be copied.
The parameters it gets are exactly the same as the callback function
in File::Find. That is $_, $File::Find::dir and $File::Find::name.

If this function returns a false value, the file is skipped.

 Ex.

  UpdateDir 'c:\dir' => 'e:\dir', sub {print '.'};
  UpdateDir 'c:\dir' => 'e:\dir', sub {if (/^s/i) {print '.'}};

=item FillInDir

 FillInDir $SourceDirectory, $DestDirectory [, \&callback]

Copy the files from $SourceDir not present in $DestDir. Processes subdirectories!
The &callback works the same as in UpdateDir.

=item Compress

 Compress $filename [, ...]

Compresses the file(s) or directories using the transparent WinNT compression
(The same as checking the "Compressed" checkbox in Explorer properties
fo the file).

It doesn't compress all files and subdirectories in a directory you
specify. Use ComressDir for that. Compress($directory) only sets the compression flag for
the directory so that the new files are compressed by default. 

WinNT only!

REM: Together with other compression related functions based
on DeviceIoControl() Win32 API function.

=item Uncompress

 Uncompress $filename [, ...]

Uncompresses the file(s) using the transparent WinNT compression
(The same as unchecking the "Compressed" checkbox in Explorer properties
fo the file).

WinNT only!

=item Compressed

 Compressed $filename

Checks the compression status for a file.

=item SetCompression

 SetCompression $filename [, $filename], $value

Sets the compression status for file(s). The $value should be
either 1 or 0.

=item GetCompression

 GetCompression $filename

Checks the compression status for a file.

=item CompressDir

 CompressDir $directory, ... [, \&callback]

Recursively descends the directory(ies) specified and compresses all files
and directories within. If you specify the \&callback, the specified function
gets executed for each of the files and directories. If the callback returns false,
no compression is done on the file/directory.

The parameters the callback gets are exactly the same as the callback function
in File::Find. That is $_, $File::Find::dir and $File::Find::name.

=item UncompressDir

 UncompressDir $directory, ... [, \&callback]

The counterpart of CompressDir. 

=item AddToRecentDocs

 AddToRecentDocs $filename [, ...]

Add a shortcut(s) to the file(s) into the Recent Documents folder.
The shortcuts will appear in the Documents submenu of Start Menu.

The paths may be relative.

REM: Based on Win32 API function SHAddToRecentDocs().

=item EmptyRecentDocs

 EmptyRecentDocs;

Deletes all shortcuts from the Recent Documents folder.

REM: Based on Win32 API function SHAddToRecentDocs(). Strange huh?

=item WriteToINI

 WriteToINI $INIfile, $section, $name1 => $value [, $name2 => $value2 [, ...]]

Copies a string into the specified section of the specified initialization file.
You may pass several name/value pairs at once.

Returns 1 if successful, undef otherwise. See Win32::GetLastError &
Win32::FormatMessage(Win32::GetLastError) if failed for the error code and message.

REM: Based on Win32 API function WritePrivateProfileString().

=item WriteToWININI

 WriteToWININI $section, $name1 => $value1 [, $name2 => $value2 [, ...]]

Copies a string into the specified section of WIN.INI.
You may pass several name/value pairs at once.

Please note that some values or sections of WIN.INI and some other INI
files are mapped to registry so they do not show up
in the INI file even if they were successfully written!

REM: Based on Win32 API function WriteProfileString().

=item ReadINI

    $value = ReadINI $INIfile, $section, $name [, $defaultvalue]

Reads a value from an INI file. If you do not specify the default
and the value is not found you'll get undef.

REM: Based on Win32 API function GetPrivateProfileString().

=item ReadWININI

    $value = ReadWININI $section, $name [, $defaultvalue]

Reads a value from WIN.INI file. If you do not specify the default
and the value is not found you'll get undef.

Please note that some values or sections of WIN.INI and some other INI
files are mapped to registry so even that they do not show up
in the INI file this function will find and read them!

REM: Based on Win32 API function GetProfileString().

=item DeleteFromINI

 DeleteFromINI $INIfile, $section, @names_to_delete

Delete a value from an INI file.

REM: Based on Win32 API function WritePrivateProfileString().

=item DeleteFromWININI

 DeleteFromWININI $section, @names_to_delete

Delete a value from WIN.INI.

REM: Based on Win32 API function WriteProfileString().

=item ReadINISections

 @sections = ReadINISections($inifile);
 \@sections = ReadINISections($inifile);
 ReadINISections($inifile,\@sections);

Enumerate the sections in a INI file. If you do not specify the INI file,
it enumerates the contents of win.ini.

REM: Based on Win32 API function GetPrivateProfileString().

=item ReadINISectionKeys

 @sections = ReadINISectionKeys($inifile, $section);
 \@sections = ReadINISectionKeys($inifile, $section);
 ReadINISectionKeys($inifile, $section, \@sections);

Enumerate the keys in a section of a INI file. If you do not specify the
INI file, it enumerates the contents of win.ini.

REM: Based on Win32 API function GetPrivateProfileString().

=item OpenDialog

 $filename = OpenDialog \%parameters [, $defaultfilename]
 @filenames = OpenDialog \%parameters [, $defaultfilename]

 $filename = OpenDialog %parameters [, $defaultfilename]
 @filenames = OpenDialog %parameters [, $defaultfilename]

Creates the standard Open dialog allowing you to select some files.

Returns a list of selected files or undef if the user pressed [Escape].
It also sets two global variables :

 $Win32::FileOp::ReadOnly = the user requested a readonly access.
 $Win32::FileOp::SelectedFilter = the id of filter selected in the dialogbox

 %parameters
  title => the title for the dialog, default is 'Open'
        'Open file'
  filters => definition of file filters
        { 'Filter 1' => '*.txt;*.doc', 'Filter 2' => '*.pl;*.pm'}
        [ 'Filter 1' => '*.txt;*.doc', 'Filter 2' => '*.pl;*.pm']
        [ 'Filter 1' => '*.txt;*.doc', 'Filter 2' => '*.pl;*.pm' , $default]
        "Filter 1\0*.txt;*.doc\0Filter 2\0*.pl;*.pm"
  defaultfilter => the number of the default filter counting from 1.
                   Please keep in mind that hashes do not preserve
                   ordering!
  dir => the initial directory for the dialog, default is the current directory
  filename => the default filename to be showed in the dialog
  extension => the default extension, this function appends this extension to
               the filename if the user fails to type an extension. This
               string can be any length, but only the first three characters
               are appended. The string should not contain a period (.).
  handle => the handle to the window which will own this dialog
            Default is the console of the perl script.
            If you do not want to tie the dialog to any window use
            handle => 0
  options => options for the dialog, see bellow OFN_... constants

There is a little problem with the underlying function. You have to
preallocate a buffer for the selected filenames and if the buffer is too
smallyou will not get any results. I've consulted this with the guys on
Perl-Win32-Users and there is not any nice solution. The defalut size of
buffer is 256B if the options do not include OFN_ALLOWMULTISELECT and
64KB if they do. You may change the later via variable
$Win32::FileOp::BufferSize.

REM: Based on Win32 API function GetOpenFileName().

=item SaveAsDialog

Creates the Save As dialog box, parameters are the same as for OpenDialog.

=item BrowseForFolder

 BrowseForFolder [$title [, $rootFolder [, $options]]]

Creates the standard "Browse For Folder" dialog.
The $title specifies the text to be displayed below the title of the dialog.
The $rootFolder may be one of the C<CSIDL_>... constants.
For $options you should use the C<BIF_>... constants. Description
of the constants is bellow.

REM: Based on Win32 API function GetSaveFileName().

=item Map

 Map $drive => $share;
 $drive = Map $share;
 Map $drive => $share, \%options;
 $drive = Map $share, \%options;

Map a drive letter or LTPx to a network resource. If successfull returns the drive letter/LPTx.

If you do not specify the drive letter, the function uses the last free
letter. Since the function doesn't require the ':' in the drive name you
may use the function like this:

 Map H => '\\\\server\share';
 as well as
 Map 'H:' => '\\\\server\share';

 Options:
  persistent = 0/1, should the connection be restored on next logon?
  user       = username to be used to connect the device
  passwd     = password to be used to connect the device
  overwrite  = 0/1, should the drive be remapped if it was already connected?

 Example:
  Map I => '\\\\servername\share', {persistent=>1,overwrite=>1};

REM: Based on Win32 API function WNetAddConnection3().

=item Disconnect

 Disconnect $drive_or_share;
 Disconnect $drive_or_share, \%options;

Breaks an existing network connection. It can also be used to remove
remembered network connections that are not currently connected.

$drive_or_share specifies the name of either the redirected local device
or the remote network resource to disconnect from. If this parameter
specifies a redirected local resource, only the specified redirection is
broken; otherwise, all connections to the remote network resource are
broken. 

 Options:
  persistent = 0/1, if you do not use persistent=>1, the connection will be closed, but
               the drive letter will still be mapped to the device
  force      = 0/1, disconnect even if there are some open files

 See also: Unmap

REM: Based on Win32 API function WNetCancelConnection2().

=item Unmap

 Unmap $drive_or_share;
 Unmap $drive_or_share, \%options;

The only difference from Disconnect is that persistent=>1 is the default.

REM: Based on Win32 API function WNetCancelConnection2().

=item Mapped

 %drives = Mapped;
 $share = Mapped $drive;
 $drive = Mapped $share; # currently not implemented !!!

This function retrieves the name of the network resource associated with a local device.
Or vice versa.

If you do not specify any parameter, you get a hash of drives and shares.

To get the error message from most of these functions, you should not use $!, but
Win32::FormatMessage(Win32::GetLastError())!

REM: Based on Win32 API function WNetGetConnection().

=back

=head2 Options

=over 2

=item FOF_

 FOF_SILENT = do not show the progress dialog
 FOF_RENAMEONCOLLISION = rename the file in case of collision
            ('file.txt' -> 'Copy of file.txt')
 FOF_NOCONFIRMATION = do not show the confirmation dialog
 FOF_ALLOWUNDO = send file(s) to RecycleBin instead of deleting
 FOF_FILESONLY = skip directories
 FOF_SIMPLEPROGRESS = do not show the filenames in the process dialog
 FOF_NOCONFIRMMKDIR = do not confirm creating directories
 FOF_NOERRORUI = do not report errors
 FOF_NOCOPYSECURITYATTRIBS = do not copy security attributes

=item OFN_

 OFN_ALLOWMULTISELECT

Specifies that the File Name list box allows multiple selections. If you
also set the OFN_EXPLORER flag, the dialog box uses the Explorer-style
user interface; otherwise, it uses the old-style user interface.

 OFN_CREATEPROMPT

If the user specifies a file that does not exist, this flag causes the
dialog box to prompt the user for permission to create the file. If the
user chooses to create the file, the dialog box closes and the function
returns the specified name; otherwise, the dialog box remains open.

 OFN_EXPLORER

Since I cannot implement hook procedures through Win32::API (AFAIK),
this option in not necessary.

 OFN_FILEMUSTEXIST

Specifies that the user can type only names of existing files in the
File Name entry field. If this flag is specified and the user enters an
invalid name, the dialog box procedure displays a warning in a message
box. If this flag is specified, the OFN_PATHMUSTEXIST flag is also used.

 OFN_HIDEREADONLY

Hides the Read Only check box.

 OFN_LONGNAMES    

For old-style dialog boxes, this flag causes the dialog box to use long
filenames. If this flag is not specified, or if the OFN_ALLOWMULTISELECT
flag is also set, old-style dialog boxes use short filenames (8.3
format) for filenames with spaces. Explorer-style dialog boxes ignore
this flag and always display long filenames.

 OFN_NOCHANGEDIR    

Restores the current directory to its original value if the user changed
the directory while searching for files.

 OFN_NODEREFERENCELINKS

Directs the dialog box to return the path and filename of the selected
shortcut (.LNK) file. If this value is not given, the dialog box returns
the path and filename of the file referenced by the shortcut

 OFN_NOLONGNAMES    

For old-style dialog boxes, this flag causes the dialog box to use short
filenames (8.3 format). Explorer-style dialog boxes ignore this flag and
always display long filenames.

 OFN_NONETWORKBUTTON

Hides and disables the Network button.

 OFN_NOREADONLYRETURN

Specifies that the returned file does not have the Read Only check box
checked and is not in a write-protected directory.

 OFN_NOTESTFILECREATE    

Specifies that the file is not created before the dialog box is closed.
This flag should be specified if the application saves the file on a
create-nonmodify network sharepoint. When an application specifies this
flag, the library does not check for write protection, a full disk, an
open drive door, or network protection. Applications using this flag
must perform file operations carefully, because a file cannot be
reopened once it is closed.

 OFN_NOVALIDATE    

Specifies that the dialog boxes allow invalid characters in the returned
filename. 

 OFN_OVERWRITEPROMPT    

Causes the Save As dialog box to generate a message box if the selected
file already exists. The user must confirm whether to overwrite the
file.

 OFN_PATHMUSTEXIST    

Specifies that the user can type only valid paths and filenames. If this
flag is used and the user types an invalid path and filename in the File
Name entry field, the dialog box function displays a warning in a
message box.

 OFN_READONLY    

Causes the Read Only check box to be checked initially when the dialog
box is created. If the check box is checked when the dialog box is closed
$Win32::FileOp::ReadOnly is set to true.

 OFN_SHAREAWARE    

Specifies that if a call to the OpenFile function fails because of a
network sharing violation, the error is ignored and the dialog box
returns the selected filename. 

 OFN_SHOWHELP

Causes the dialog box to display the Help button. The hwndOwner member
must specify the window to receive the HELPMSGSTRING registered messages
that the dialog box sends when the user clicks the Help button.

=item BIF_

 BIF_DONTGOBELOWDOMAIN

Does not include network folders below the domain level in the tree view
control.

 BIF_RETURNONLYFSDIRS

Only returns file system directories. If the user selects folders that
are not part of the file system, the OK button is grayed.

 BIF_RETURNFSANCESTORS

Only returns file system ancestors. If the user selects anything other
than a file system ancestor, the OK button is grayed.

This option is strange, cause it seems to allow you to select only computers.
I don't know the definition of a filesystem ancestor, but I didn't think
it would be a computer. ?-|

 BIF_BROWSEFORCOMPUTER

Only returns computers. If the user selects anything other than a
computer, the OK button is grayed.

 BIF_BROWSEFORPRINTER

Only returns printers. If the user selects anything other than a
printer, the OK button is grayed.

 BIF_STATUSTEXT

Since it is currently impossible to define callbacks, this options is
useless. 


=item CSIDL_

This is a list of available options for BrowseForFolder().

CSIDL_BITBUCKET

Recycle bin --- file system directory containing file objects in the
user's recycle bin. The location of this directory is not in the
registry; it is marked with the hidden and system attributes to prevent
the user from moving or deleting it.

CSIDL_CONTROLS

Control Panel --- virtual folder containing icons for the control panel
applications.

CSIDL_DESKTOP

Windows desktop --- virtual folder at the root of the name space.

CSIDL_DESKTOPDIRECTORY

File system directory used to physically store file objects on the
desktop (not to be confused with the desktop folder itself).

CSIDL_DRIVES

My Computer --- virtual folder containing everything on the local
computer: storage devices, printers, and Control Panel. The folder may
also contain mapped network drives.

CSIDL_FONTS

Virtual folder containing fonts.

CSIDL_NETHOOD

File system directory containing objects that appear in the network
neighborhood.

CSIDL_NETWORK

Network Neighborhood --- virtual folder representing the top level of the
network hierarchy.

CSIDL_PERSONAL

File system directory that serves as a common repository for documents.

CSIDL_PRINTERS

Printers folder --- virtual folder containing installed printers.

CSIDL_PROGRAMS

File system directory that contains the user's program groups (which are
also file system directories).

CSIDL_RECENT

File system directory that contains the user's most recently used
documents.

CSIDL_SENDTO

File system directory that contains Send To menu items.

CSIDL_STARTMENU

File system directory containing Start menu items.

CSIDL_STARTUP

File system directory that corresponds to the user's Startup program
group.

CSIDL_TEMPLATES

File system directory that serves as a common repository for document
templates.

Not all options make sense in all functions!

=back

=head2 Variables

 $Win32::FileOp::ProgressTitle

This variable (if defined) contains the text to be displayed on
the progress dialog if using FOF_SIMPLEPROGRESS. This allows you
to present the user with your own message about what is happening
to his computer.

If the options for the call do not contain FOF_SIMPLEPROGRESS, this
variable is ignored.

=head2 Examples

    use Win32::FileOp;

    CopyConfirm ('c:\temp\kinter.pl' => 'c:\temp\copy\\',
                 ['\temp\kinter1.pl', 'temp\kinter2.pl']
                 => ['c:\temp\copy1.pl', 'c:\temp\copy2.pl']);

    $Win32::FileOp::ProgressTitle = "Moving the temporary files ...";
    MoveEx 'c:\temp\file.txt' => 'd:\temp\\',
           ['c:\temp\file1.txt','c:\temp\file2.txt'] => 'd:\temp',
           FOF_RENAMEONCOLLISION | FOF_SIMPLEPROGRESS;
    undef $Win32::FileOp::ProgressTitle;

    Recycle 'c:\temp\kinter.pl';

=head2 Handles

All the functions keep Win32::API handles between calls. If you want to free the handles
you may undefine them, but NEVER EVER set them to anything else than undef !!!
Even  "$handlename = $handlename;" would destroy the handle without repair!
See docs for Lazy.pm for explanation.

List of handles and functions that use them:

 $Win32::FileOp::fileop : Copy, CopyEx, CopyConfirm, Move, MoveEx, MoveConfirm
  Delete, DeleteEx, DeleteConfirm, Recycle, RecycleEx, RecycleConfirm
 $Win32::FileOp::movefileex : MoveFileEx MoveFile MoveAtReboot
 $Win32::FileOp::movefileexDel : DeleteAtReboot
 $Win32::FileOp::copyfile : CopyFile
 $Win32::FileOp::writeINI : WriteToINI MoveAtReboot DeleteAtReboot
 $Win32::FileOp::writeWININI : WriteToWININI
 $Win32::FileOp::deleteINI : DeleteFromINI
 $Win32::FileOp::deleteWININI : DeleteFromWININI
 $Win32::FileOp::readINI : ReadINI
 $Win32::FileOp::readWININI : ReadWININI
 $Win32::FileOp::GetOpenFileName : OpenDialog
 $Win32::FileOp::GetSaveFileName : SaveAsDialog
 $Win32::FileOp::SHAddToRecentDocs : AddToRecentDocs EmptyRecentDocs
 $Win32::FileOp::DesktopHandle
 $Win32::FileOp::WindowHandle : OpenDialog SaveDialog
 $Win32::FileOp::WNetAddConnection3 : Map
 $Win32::FileOp::WNetGetConnection : Mapped
 $Win32::FileOp::WNetCancelConnection2 : Unmap Disconnect Map
 $Win32::FileOp::GetLogicalDrives : FreeDriveLetters Map

=head2 Notes

By default all functions are exported! If you do not want to polute your
namespace too much import only the functions you need.
You may import either single functions or whole groups.

The available groups are :

 BASIC = Move..., Copy..., Recycle... and Delete... functions plus constants
 _BASIC = FOF_... constants only
 HANDLES = DesktopHandle GetDesktopHandle WindowHandle GetWindowHandle
 INI = WriteToINI WriteToWININI ReadINI ReadWININI ReadINISectionKeys DeleteFromINI DeleteFromWININI
 DIALOGS = OpenDialog SaveAsDialog plus OFN_... constants
 _DIALOGS = only OFN_... constants
 RECENT = AddToRecentDocs, EmptyRecentDocs
 DIRECTORY = UpdateDir, FillInDir
 COMPRESS => Compress Uncompress Compressed SetCompression GetCompression
 MAP => Map Unmap Disconnect Mapped

Examples:

 use Win32::FileOp qw(:BASIC GetDesktopHandle);
 use Win32::FileOp qw(:_BASIC MoveEx CopyEx);
 use Win32::FileOp qw(:INI :_DIALOGS SaveAsDialog);

This module contains all methods from Win32::RecycleBin. The only change
you have to do is to use this module instead of the old Win32::RecycleBin.
Win32:RecycleBin is not supported anymore!

=head2 TO-DO

WNetConnectionDialog, WNetDisconnectDialog

=head2 AUTHORS

 Module built by :
  Jan Krynicky <Jenda@Krynicky.cz>
  $Bill Luebkert <dbe@wgn.net>
  Mike Blazer <blazer@mail.nevalink.ru>
  Aldo Calpini <a.calpini@romagiubileo.it>
  Michael Yamada <myamada@gj.com>

=cut



