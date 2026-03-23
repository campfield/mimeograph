#
# Exit immediately with a formatted error message.
#
def exit_with_message(message, exit_code = 1)
  handle_message(message, 'ERROR')
  exit(exit_code)
end
