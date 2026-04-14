using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using MassTransit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Example
{
    public class Sender : BackgroundService
    {
        static Timer _timer;
        readonly IBusControl _bus;
        readonly IServiceScopeFactory _factory;

        readonly ILogger _logger;

        List<Exception> _exceptionList = new List<Exception>();
        Exception _lastException;

        public Sender(ILoggerFactory loggerFactory, IBusControl bus, IServiceScopeFactory factory)
        {
            _logger = loggerFactory.CreateLogger("Publishd");
            _bus = bus;
            _factory = factory;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            await _bus.WaitForHealthStatus(BusHealthStatus.Healthy, stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                await using var scope = _factory.CreateAsyncScope();

                var bus = scope.ServiceProvider.GetRequiredService<IScopedBus>();

                await Publish(bus);

                await Task.Delay(3000, stoppingToken);
                
                var health = _bus.CheckHealth();
                if(health.Status !=  BusHealthStatus.Healthy)
                {
                    Console.WriteLine("The bus health is:  " + health.Status);
                }
            }
        }


        async Task Publish(IScopedBus bus)
        {
            var count = Counter.IncrementPublish();

            var message = new TestMessage
            {
                Counter = count,
                Timestamp = DateTime.Now
            };
            try
            {
                await bus.Publish(message);
                Console.WriteLine($"{DateTime.Now} [{count}] Publish : " + message);
            }
            catch (Exception e)
            {
                _logger.LogError(e, $"Publish Exception for message : {message} " + e.Message);
                _exceptionList.Add(e);
                _lastException = e;
            }
        }
    }
}