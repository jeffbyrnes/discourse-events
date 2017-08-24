# name: discourse-events
# about: Tools for adding event details to topics in Discourse
# version: 0.1
# authors: Angus McLeod

register_asset 'stylesheets/events.scss'

Discourse.top_menu_items.push(:agenda)
Discourse.anonymous_top_menu_items.push(:agenda)
Discourse.filters.push(:agenda)
Discourse.anonymous_filters.push(:agenda)

after_initialize do
  Category.register_custom_field_type('events_enabled', :boolean)
  add_to_serializer(:basic_category, :events_enabled) {object.custom_fields["events_enabled"]}

  # event times are stored individually as seconds since epoch so that event topic lists
  # can be ordered easily within the exist topic list query structure in Discourse core.
  Topic.register_custom_field_type('event_start', :integer)
  Topic.register_custom_field_type('event_end', :integer)

  # but a combined hash with iso8601 dates is easier to work with
  require_dependency 'topic'
  class ::Topic
    def has_event?
      self.custom_fields['event_start'].present? && self.custom_fields['event_end'].present?
    end

    def event
      return nil unless has_event?

      {
        start: Time.at(self.custom_fields['event_start']).iso8601,
        end: Time.at(self.custom_fields['event_end']).iso8601
      }
    end
  end

  add_to_serializer(:topic_view, :include_event?) {object.topic.has_event?}
  add_to_serializer(:topic_view, :event) {object.topic.event}

  TopicList.preloaded_custom_fields << "event_start" if TopicList.respond_to? :preloaded_custom_fields
  TopicList.preloaded_custom_fields << "event_end" if TopicList.respond_to? :preloaded_custom_fields

  require_dependency 'topic_list_item_serializer'
  class ::TopicListItemSerializer
    attributes :event

    def include_event?
      object.has_event?
    end

    def event
      object.event
    end
  end

  PostRevisor.track_topic_field(:event)

  PostRevisor.class_eval do
    track_topic_field(:event) do |tc, event|
      event_start = event['start'].to_datetime.to_i
      event_end = event['end'].to_datetime.to_i

      tc.record_change('event_start', tc.topic.custom_fields['event_start'], event_start)
      tc.record_change('event_end', tc.topic.custom_fields['event_start'], event_start)

      tc.topic.custom_fields['event_start'] = event_start
      tc.topic.custom_fields['event_end'] = event_end
    end
  end

  DiscourseEvent.on(:post_created) do |post, opts, user|
    if post.is_first_post? && opts[:event]
      topic = Topic.find(post.topic_id)

      event_start = opts[:event]['start']
      event_end = opts[:event]['end']

      topic.custom_fields['event_start'] = event_start.to_datetime.to_i if event_start
      topic.custom_fields['event_end'] = event_end.to_datetime.to_i if event_end
      topic.save!
    end
  end

  require_dependency 'topic_query'
  class ::TopicQuery
    SORTABLE_MAPPING["agenda"] = "custom_fields.event_start"

    def list_agenda
      @options[:order] = "agenda"
      topics = create_list(:agenda, ascending: "true")
    end
  end

  load File.expand_path("../lib/category-events.rb", __FILE__)
end