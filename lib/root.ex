defmodule Root do
  def start do
    EngagementTracker.start_link()

    Dispatcher.start_link()

    print_sup_name = GenericSupervisor.generate_supervisor_name(Print)
    eng_sup_name = GenericSupervisor.generate_supervisor_name(Engagement)
    sent_sup_name = GenericSupervisor.generate_supervisor_name(Sentiment)
    censor_sup_name = GenericSupervisor.generate_supervisor_name(Censor)

    GenericSupervisor.start_link(Print, 3)
    GenericSupervisor.start_link(Engagement, 3)
    GenericSupervisor.start_link(Sentiment, 3)
    GenericSupervisor.start_link(Censor, 3)

    w1 = WorkerPoolManager.start_link(print_sup_name, Print)

    true = LoadBalancer.start_link(print_sup_name, w1)
    true = LoadBalancer.start_link(eng_sup_name, nil)
    true = LoadBalancer.start_link(sent_sup_name, nil)
    true = LoadBalancer.start_link(censor_sup_name, nil)

    Aggregator.start_link()
    Batcher.start_link()
    ReadSupervisor.start_link()
  end
end
