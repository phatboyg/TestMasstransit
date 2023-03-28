using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using MassTransit;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Example
{
    public class Sender : BackgroundService
    {
        readonly IBusControl _bus;

        readonly ILogger _logger;

        private static Timer _timer;

        private List<Exception> _exceptionList = new List<Exception>();
        private Exception _lastException;

        public Sender(ILoggerFactory loggerFactory, IBusControl bus)
        {
            _logger = loggerFactory.CreateLogger("Publishd");
            _bus = bus;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            await WaitForHealthyBus(stoppingToken);

            while (!stoppingToken.IsCancellationRequested)
            {
                await Publish();

                await Task.Delay(30000, stoppingToken);
            }
        }


        async Task WaitForHealthyBus(CancellationToken cancellationToken)
        {
            BusHealthResult result;
            do
            {
                result = _bus.CheckHealth();

                await Task.Delay(100, cancellationToken);
            } while (result.Status != BusHealthStatus.Healthy);
        }

        async Task Publish()
        {
            var count = Counter.IncrementPublish();

            var message = new TestMessage
            {
                Counter = count,
                Timestamp = DateTime.Now
            };
            try
            {
                await _bus.Publish(message);
                Console.WriteLine($"{DateTime.Now} [{count}] Publish : " + message.ToString());
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