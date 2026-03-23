#
# Return the filename stripped of its path and extension.
#
def file_basename(source_file)
  exit_with_message('file_basename called without a source_file argument.') unless source_file
  File.basename(source_file, File.extname(source_file))
end
