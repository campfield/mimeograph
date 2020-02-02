#
# Debugging function used to generate pretty JSON when reading through compiled configuration settings.
#
def format_json(
  source_json = nil
)

  exit_with_message("no JSON passed to function [format_json].") unless source_json

  exit_with_message("Data passed to [format_json] is not valid JSON.") unless JSON.parse(source_json)

  JSON.pretty_generate(source_json)

end
