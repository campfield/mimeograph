#
# Form a sub-structure of a synced_fs_object-type sub-stanza populate it into a
#  the JSON format used by the storage manipulation section of mimeograph's code.
#
def populate_hash_synced_fs_objects(
  synced_fs_objects = nil,
  provider = 'virtualbox'
)

  exit_with_message("no synced object hash passed to function [populate_hash_synced_fs_objects].") unless synced_fs_objects

  synced_fs_objects = {
    'providers' => {
      provider => {
        'instance' => {
          'storage' => {
            'filesystems' => {
              'synced_fs_objects' => synced_fs_objects
            }
          }
        }
      }
    }
  }

  synced_fs_objects

end
