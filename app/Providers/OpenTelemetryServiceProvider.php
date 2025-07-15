<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use OpenTelemetry\API\Globals;
use OpenTelemetry\API\Trace\TracerInterface;
use OpenTelemetry\Contrib\Otlp\OtlpHttpTransportFactory;
use OpenTelemetry\Contrib\Otlp\SpanExporter;
use OpenTelemetry\SDK\Common\Attribute\Attributes;
use OpenTelemetry\SDK\Common\Export\Http\PsrTransportFactory;
use OpenTelemetry\SDK\Resource\ResourceInfo;
use OpenTelemetry\SDK\Resource\ResourceInfoFactory;
use OpenTelemetry\SDK\Trace\SpanProcessor\SimpleSpanProcessor;
use OpenTelemetry\SDK\Trace\TracerProvider;
use OpenTelemetry\SemConv\ResourceAttributes;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Http\Request;

class OpenTelemetryServiceProvider extends ServiceProvider
{
    private TracerInterface $tracer;

    /**
     * Register services.
     */
    public function register(): void
    {
        $this->app->singleton(TracerInterface::class, function () {
            // Build resource attributes from config
            $attributes = [
                ResourceAttributes::SERVICE_NAME => config('opentelemetry.service_name'),
                ResourceAttributes::SERVICE_VERSION => config('opentelemetry.service_version'),
            ];

            // Add custom resource attributes
            foreach (config('opentelemetry.resource_attributes', []) as $key => $value) {
                $attributes[$key] = $value;
            }

            $resource = ResourceInfoFactory::emptyResource()->merge(
                ResourceInfo::create(Attributes::create($attributes))
            );

            $transport = (new OtlpHttpTransportFactory())->create(
                config('opentelemetry.exporter.endpoint') . '/v1/traces',
                'application/json'
            );

            $exporter = new SpanExporter($transport);
            $spanProcessor = new SimpleSpanProcessor($exporter);

            $tracerProvider = TracerProvider::builder()
                ->addSpanProcessor($spanProcessor)
                ->setResource($resource)
                ->build();

            Globals::registerInitializer(function () use ($tracerProvider) {
                return $tracerProvider;
            });

            return $tracerProvider->getTracer(
                config('opentelemetry.service_name'),
                config('opentelemetry.service_version')
            );
        });
    }

    /**
     * Bootstrap services.
     */
    public function boot(): void
    {
        $this->tracer = $this->app->make(TracerInterface::class);

        // Trace HTTP requests
        $this->traceHttpRequests();

        // Trace database queries
        $this->traceDatabaseQueries();

        // Trace logs
        $this->traceLogs();
    }

    /**
     * Trace HTTP requests
     */
    private function traceHttpRequests(): void
    {
        $this->app['events']->listen('kernel.handled', function ($request, $response) {
            $span = $this->tracer->spanBuilder('http.request')
                ->setAttribute('http.method', $request->method())
                ->setAttribute('http.url', $request->fullUrl())
                ->setAttribute('http.target', $request->path())
                ->setAttribute('http.host', $request->getHost())
                ->setAttribute('http.scheme', $request->getScheme())
                ->setAttribute('http.status_code', $response->getStatusCode())
                ->setAttribute('http.user_agent', $request->userAgent())
                ->startSpan();

            // Add request headers
            foreach ($request->headers->all() as $key => $value) {
                $span->setAttribute("http.request.header.$key", implode(',', $value));
            }

            $span->end();
        });
    }

    /**
     * Trace database queries
     */
    private function traceDatabaseQueries(): void
    {
        DB::listen(function ($query) {
            $span = $this->tracer->spanBuilder('db.query')
                ->setAttribute('db.system', 'postgresql')
                ->setAttribute('db.statement', $query->sql)
                ->setAttribute('db.operation', $this->extractOperation($query->sql))
                ->setAttribute('db.execution_time_ms', $query->time)
                ->startSpan();

            // Add bindings as attributes
            if (!empty($query->bindings)) {
                $span->setAttribute('db.bindings', json_encode($query->bindings));
            }

            $span->end();
        });
    }

    /**
     * Trace logs
     */
    private function traceLogs(): void
    {
        Log::listen(function ($event) {
            $span = $this->tracer->spanBuilder('log.entry')
                ->setAttribute('log.level', $event->level)
                ->setAttribute('log.message', $event->message)
                ->setAttribute('log.context', json_encode($event->context))
                ->startSpan();

            $span->end();
        });
    }

    /**
     * Extract operation from SQL query
     */
    private function extractOperation(string $sql): string
    {
        $sql = trim($sql);
        $operation = strtoupper(explode(' ', $sql)[0]);
        
        return match ($operation) {
            'SELECT' => 'SELECT',
            'INSERT' => 'INSERT',
            'UPDATE' => 'UPDATE',
            'DELETE' => 'DELETE',
            'CREATE' => 'CREATE',
            'DROP' => 'DROP',
            'ALTER' => 'ALTER',
            default => 'OTHER',
        };
    }
}