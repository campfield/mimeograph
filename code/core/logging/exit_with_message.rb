#
# Blindly exit with text message and generic exit codes.
#
def exit_with_message(
  message = nil,
  exit_code = 1
)

  handle_message(message, 'ERROR')

  exit(exit_code)

end
