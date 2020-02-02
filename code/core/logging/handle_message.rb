#
# Print a mesage to stdout with a prefix title.
#  The message_titles_display is awkward and should be rewritten.
#
def handle_message(
  message,
  message_title = "INFO",
  message_titles_display = [
    "ERROR",
    "INFO",
    "WARNING"
  ]
)
  if !message_title.nil?
    return unless message_titles_display.include?(message_title)
  else
    message_title = "ERR_NO_TITLE"
  end

  if message.nil? or message.empty?
    puts "[ERROR]: no message passed to function [handle_message]."
  else
    puts "[#{message_title}]: #{message}"
  end

end
