require 'octokit'
require 'jwt'
require 'httparty'

# some configuration that you should change to reflect your own Recast.AI account
RECASTAI_USERNAME = 'grahamshllk'
RECASTAI_BOTNAME = 'github'
RECASTAI_DEV_TOKEN = ENV['RECASTAI_DEV_TOKEN']

# We will time each request in order to avoid GitHub's rate limiter.
# We are allowed 10 requests per minute without authenticating.
time_between_calls = 60 / 10

# Repeat the following for each label we want to build an intent for:
for label in ['bug', 'enhancement', 'question']

    page = 1

    # GitHub currently caps search results to 1,000 entries, but we're not going to count. We'll let GitHub do the
    # counting for us—so, loop forever.
    loop do
        before = Time.now

        begin
            # Here is the centerpiece of this code: The call to the Search API.
            issues = Octokit::Client.search_issues("label:#{label}", page: page)
        rescue Octokit::UnprocessableEntity => ex
            # GitHub will only return 1,000 results. Any requests that page beyond 1,000 will result in a 422 error
            # instead of a 200. Octokit throws an exception when we get a 422. If this happens, it's because we've seen
            # all the results.
            puts "Got all the results for #{label}. Let's move on to the next one."
            break
        rescue Octokit::TooManyRequests => ex
            puts "Rate limit exceeded"
            # `kernel#sleep` often doesn't sleep for as long as you'd like. This means that sometimes we hit the rate
            # limit despite taking the necessary precautions to avoid this. If this happens, just sleep a little longer,
            # and try again.
            sleep(time_between_calls)
            next # try endpoint again
        end

        # Notice that we also have to specify the language. There is a non-trivial chance that we have several
        # non-English issue titles in our collection, but GitHub doesn't have any data on the languages the issues are
        # written in (and why should it?). For now, we will (wrongly, but not unjustifiably) assume English. Although,
        # a better implementation would be to run these titles through a separate API that can help guess the correct
        # language.
        expressions = []
        for expression in issues['items'] do
            expressions.push({source: expression['title'], language: {isocode: 'en'}})
        end

        # And now we bulk-post the tagged titles to Recast.AI. Their otherwise excellent gem doesn't support this
        # endpoint, so we need to use raw HTTP requests to upload the data.
        result = HTTParty.post("https://api.recast.ai/v2/users/#{RECASTAI_USERNAME}/bots/#{RECASTAI_BOTNAME}/intents/#{label}/expressions/bulk_create",
                               body: {expressions: expressions},
                               headers: {'Authorization' => "Token #{RECASTAI_DEV_TOKEN}"}
        )

        # Go to the next page of search results from GitHub.
        page += 1

        # Now that we have completed the call to the GitHub Search API and the Recast.AI API, let's measure how long it
        # took. We can always sleep if we need to, in order to avoid hitting the rate limiter.
        after = Time.now
        sleepy_time = time_between_calls - (after - before)
        slept = sleep(sleepy_time) unless sleepy_time <= 0

    end
end
