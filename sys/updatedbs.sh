#!/bin/bash 

# sudo updatedb -U /run/media/peddycoartte/Backup  -o /var/lib/mlocate/Backup.db
# sudo updatedb -U /run/media/peddycoartte/Development  -o /var/lib/mlocate/Development.db
sudo updatedb -U /run/media/peddycoartte/MasterBackup  -o /var/lib/mlocate/MasterBackup.db
sudo updatedb -U /run/media/peddycoartte/OldMasterBackup  -o /var/lib/mlocate/OldMasterBackup.db

# locate -d /var/lib/mlocate/mlocate.db:/var/lib/mlocate/MasterBackup.db searchterm

#alias locateall='locate -d /var/lib/mlocate/mlocate.db:/var/lib/mlocate/MasterBackup.db'