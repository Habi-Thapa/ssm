module SimpleStateMachine
  
  def event event_name, state_transitions
    @state_machine ||= StateMachine.new self
    @state_machine.register_event event_name, state_transitions
  end
  
  def state_machine
    @state_machine
  end
  
  class StateMachine
    
    attr_reader :events

    def initialize subject
      @decorator = Decorator.new(subject)
      @events  = {}
    end
    
    def register_event event_name, state_transitions
      @events[event_name] ||= {}
      state_transitions.each do |from, to|
        @events[event_name][from.to_s] = to.to_s
        @decorator.decorate(from, to, event_name)
      end
    end

  end
  
  class Decorator

    def initialize(subject)
      @subject = subject
      @subject.send :include, InstanceMethods
      @active_record = @subject.ancestors.map {|klass| klass.to_s}.include?("ActiveRecord::Base")
      if @active_record
        @subject.send :include, ActiveRecordInstanceMethods
      else
        define_state_getter_method
        define_state_setter_method
      end
    end

    def decorate from, to, event_name
      define_state_helper_method(from)
      define_state_helper_method(to)
      define_event_method(event_name)
      decorate_event_method(event_name)
    end
    
    private

      def define_state_setter_method
        unless @subject.method_defined?('state=')
          @subject.send(:define_method, 'state=') do |new_state|
            @state = new_state.to_s
          end
        end
      end

      def define_state_getter_method
        unless @subject.method_defined?('state')
          @subject.send(:define_method, 'state') do
            @state
          end
        end
      end

      def define_event_method event_name
        unless @subject.method_defined?("#{event_name}")
          @subject.send(:define_method, "#{event_name}") {}
        end
        if @active_record
          unless @subject.method_defined?("#{event_name}!")
            @subject.send(:define_method, "#{event_name}!") {}
          end
        end
      end
    
      def define_state_helper_method state
        unless @subject.method_defined?("#{state.to_s}?")
          @subject.send(:define_method, "#{state.to_s}?") do
            self.state == state.to_s
          end
        end
      end

      def decorate_event_method event_name
        unless @subject.method_defined?("with_managed_state_#{event_name}")
          @subject.send(:define_method, "with_managed_state_#{event_name}") do |*args|
            state_machine  = self.class.state_machine
            return ssm_transition(event_name, state, state_machine.events[event_name][state]) do
              send("without_managed_state_#{event_name}", *args)
            end
          end
          @subject.send :alias_method, "without_managed_state_#{event_name}", event_name
          @subject.send :alias_method, event_name, "with_managed_state_#{event_name}"
        end
        if @active_record
          unless @subject.method_defined?("with_managed_state_#{event_name}!")
            @subject.send(:define_method, "with_managed_state_#{event_name}!") do |*args|
              state_machine  = self.class.state_machine
              return ssm_transition!(event_name, state, state_machine.events[event_name][state]) do
                send("without_managed_state_#{event_name}!", *args)
              end
            end
            @subject.send :alias_method, "without_managed_state_#{event_name}!", "#{event_name}!"
            @subject.send :alias_method, "#{event_name}!", "with_managed_state_#{event_name}!"
          end
        end
      end
    
  end
  
  
  module InstanceMethods
    
    def set_initial_state(state)
      self.state = state
    end

    private
    
      def ssm_transition(event_name, from, to)
        if to
          @next_state = to
          result = yield
          self.state = to
          send :state_transition_succeeded_callback
          result
        else
          send :illegal_state_transition_callback, event_name
        end
      end

      def state_transition_succeeded_callback
      end
    
      def illegal_state_transition_callback event_name
        # override with your own implementation, like setting errors in your model
        raise "You cannot '#{event_name}' when state is '#{state}'"
      end
  end

  module ActiveRecordInstanceMethods

    private
    
      def ssm_transition!(event_name, from, to)
        if to
          @next_state = to
          result = yield
          self.state = to
          send :state_transition_succeeded_callback!
          result
        else
          send :illegal_state_transition_callback, event_name
        end
      end

      def state_transition_succeeded_callback
        save
      end

      def state_transition_succeeded_callback!
        save!
      end
    # 
    # def cancel_state_transition
    #   @__cancel_state_transition = true
    # end
  
  end

end