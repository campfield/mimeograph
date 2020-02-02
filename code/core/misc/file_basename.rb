#
# Simply return the filename with the path and any dot-format extensions truncated.
#
def file_basename(
  source_file = nil
)

  exit_with_message("source_file value not passed to [file_basename] function.") unless source_file

  File.basename(source_file, File.extname(source_file))

end
