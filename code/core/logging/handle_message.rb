#
# Print a formatted message to stdout.
# Only messages whose title appears in display_levels are shown.
#
def handle_message(
  message,
  title  = 'INFO',
  display_levels = %w[ERROR INFO WARNING]
)
  title = title.to_s.upcase
  return unless display_levels.include?(title)

  if message.nil? || message.to_s.empty?
    puts '[ERROR]: handle_message called with no message.'
  else
    puts "[#{title}]: #{message}"
  end
end
