require_relative "../../aws_helper"

require 'aws-sdk-sns'
require 'aws-sdk-sqs'

describe ManageIQ::Providers::Amazon::CloudManager::EventCatcher::Stream do
  subject do
    ems = FactoryBot.create(:ems_amazon_with_authentication)
    described_class.new(ems)
  end
  let(:queue_url) { "https://sqs.eu-central-1.amazonaws.com/995412904407/the_queue_name" }
  let(:topic_name) { "arn:aws:sns:region:account-id:#{described_class::AWS_CONFIG_TOPIC}" }

  let(:get_queue_attributes) do
    Aws::SQS::Client.new(:stub_responses => true).stub_data(:get_queue_attributes, :attributes => {'QueueArn' => 'arn'})
  end

  describe "#find_or_create_queue" do
    context "with queue present on amazon" do
      it "finds the queue" do
        stubbed_responses = {
          :sqs => {
            :get_queue_url        => {:queue_url => queue_url},
            :get_queue_attributes => get_queue_attributes
          },
          :sns => {
            :list_topics => {
              :topics => [{:topic_arn => topic_name}]
            }
          }
        }
        with_aws_stubbed(stubbed_responses) do
          expect(subject).to receive(:sqs_get_queue_url).and_call_original
          expect(subject).not_to receive(:sqs_create_queue).and_call_original
          expect(subject.send(:find_or_create_queue)).to eq(queue_url)
        end
      end
    end

    context "with no queue present on aws" do
      context "and topic present on aws" do
        it "creates the queue" do
          stubbed_responses = {
            :sqs => {
              :get_queue_url        => 'NonExistentQueue',
              :get_queue_attributes => get_queue_attributes,
              :create_queue         => {:queue_url => queue_url}
            },
            :sns => {
              :list_topics => {
                :topics => [{:topic_arn => topic_name}]
              }
            }
          }
          with_aws_stubbed(stubbed_responses) do
            expect(subject).to receive(:sqs_get_queue_url).and_call_original
            expect(subject).to receive(:sqs_create_queue).and_call_original
            expect(subject).to receive(:subscribe_topic_to_queue).and_call_original
            expect(subject.send(:find_or_create_queue)).to eq(queue_url)
          end
        end
      end
    end
  end

  describe "find or create topic" do
    before do
      allow(subject).to receive(:create_topic).and_return(Aws::SNS::Topic.new(:stub_responses => true, :arn => topic_name))
    end

    context "topic already present on aws" do
      it "gets it" do
        stubbed_responses = {
          :sqs => {
            :get_queue_url => {:queue_url => queue_url},
          },
          :sns => {
            :list_topics => {
              :topics => [:topic_arn => topic_name]
            }
          }
        }
        with_aws_stubbed(stubbed_responses) do
          expect(subject).not_to receive(:create_topic)
          expect(subject.send(:sns_topic).arn).to eq(topic_name)
        end
      end
    end

    context "no topic present on aws" do
      it "creates one" do
        stubbed_responses = {
          :sqs => {
            :get_queue_url => {:queue_url => queue_url},
          },
          :sns => {
            :list_topics => {
              :topics => []
            }
          }
        }
        with_aws_stubbed(stubbed_responses) do
          expect(subject.send(:sns_topic).arn).to eq(topic_name)
        end
      end
    end
  end

  context "#parse_event" do
    let(:message) do
      body = File.read(File.join(File.dirname(__FILE__), "sqs_message.json"))
      Aws::SQS::Types::Message.new(:body => body, :message_id => 1)
    end

    it "parses a SNS Message" do
      expect(subject.send(:parse_event, message)).to include('messageId'   => 1,
                                                             "messageType" => "ConfigurationItemChangeNotification",
                                                             "eventType"   => "AWS_EC2_Instance_UPDATE")
    end
  end

  context "#poll" do
    it "yields an event" do
      message_body = File.read(File.join(File.dirname(__FILE__), "sqs_message.json"))
      stubbed_responses = {
        :sqs => {
          :receive_message => [
            {
              :messages => [
                {
                  :body           => message_body,
                  :receipt_handle => 'receipt_handle',
                  :message_id     => 'id'
                }
              ]
            },
            # second message raises an exception
            "ServiceError"
          ]
        }
      }
      with_aws_stubbed(stubbed_responses) do
        allow(subject).to receive(:find_or_create_queue).and_return(queue_url)
        allow(subject).to receive(:parse_event).and_return(message_body)
        polled_event = nil
        expect do
          subject.poll do |event|
            polled_event = event
          end
        end.to raise_exception(described_class::ProviderUnreachable)
        expect(polled_event).to eq(message_body)
      end
    end
  end
end
