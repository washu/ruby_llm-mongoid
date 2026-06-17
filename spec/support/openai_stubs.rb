# frozen_string_literal: true

# Helpers for stubbing OpenAI HTTP calls with WebMock.
module OpenAIStubs
  BASE_URL = "https://api.openai.com/v1"

  def stub_openai_chat(content: "Hello!", input_tokens: 10, output_tokens: 5,
                       model: "gpt-4o-mini", tool_calls: nil)
    message = { "role" => "assistant", "content" => content }
    message["tool_calls"] = tool_calls if tool_calls

    body = {
      "id" => "chatcmpl-test",
      "object" => "chat.completion",
      "model" => model,
      "choices" => [{ "index" => 0, "message" => message, "finish_reason" => "stop" }],
      "usage" => {
        "prompt_tokens" => input_tokens,
        "completion_tokens" => output_tokens,
        "total_tokens" => input_tokens + output_tokens
      }
    }

    stub_request(:post, "#{BASE_URL}/chat/completions")
      .to_return(
        status: 200,
        body: body.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_openai_chat_error(message: "Internal server error", status: 500)
    stub_request(:post, "#{BASE_URL}/chat/completions")
      .to_return(
        status: status,
        body: { "error" => { "message" => message, "type" => "server_error" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def openai_tool_call(id: "call_abc123", name: "get_weather", arguments: { "city" => "NYC" })
    [{
      "id" => id,
      "type" => "function",
      "function" => { "name" => name, "arguments" => arguments.to_json }
    }]
  end
end

RSpec.configure do |config|
  config.include OpenAIStubs
end
