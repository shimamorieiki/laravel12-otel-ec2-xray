<?php

return [
    /*
    |--------------------------------------------------------------------------
    | OpenTelemetry Service Configuration
    |--------------------------------------------------------------------------
    |
    | Configure your OpenTelemetry service settings here.
    |
    */

    'service_name' => env('OTEL_SERVICE_NAME', 'laravel-app'),
    'service_version' => env('OTEL_SERVICE_VERSION', '1.0.0'),

    /*
    |--------------------------------------------------------------------------
    | OpenTelemetry Exporter Configuration
    |--------------------------------------------------------------------------
    |
    | Configure the OpenTelemetry exporter settings.
    |
    */

    'exporter' => [
        'endpoint' => env('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://localhost:4318'),
        'protocol' => env('OTEL_EXPORTER_OTLP_PROTOCOL', 'http/json'),
        'headers' => env('OTEL_EXPORTER_OTLP_HEADERS', ''),
        'timeout' => env('OTEL_EXPORTER_OTLP_TIMEOUT', 10),
    ],

    /*
    |--------------------------------------------------------------------------
    | Trace Configuration
    |--------------------------------------------------------------------------
    |
    | Configure trace-specific settings.
    |
    */

    'traces' => [
        'enabled' => env('OTEL_TRACES_ENABLED', true),
        'exporter' => env('OTEL_TRACES_EXPORTER', 'otlp'),
        'sampler' => env('OTEL_TRACES_SAMPLER', 'always_on'),
        'sampler_ratio' => env('OTEL_TRACES_SAMPLER_RATIO', 1.0),
    ],

    /*
    |--------------------------------------------------------------------------
    | Metrics Configuration
    |--------------------------------------------------------------------------
    |
    | Configure metrics-specific settings.
    |
    */

    'metrics' => [
        'enabled' => env('OTEL_METRICS_ENABLED', true),
        'exporter' => env('OTEL_METRICS_EXPORTER', 'otlp'),
        'interval' => env('OTEL_METRICS_EXPORT_INTERVAL', 60),
    ],

    /*
    |--------------------------------------------------------------------------
    | Logs Configuration
    |--------------------------------------------------------------------------
    |
    | Configure logs-specific settings.
    |
    */

    'logs' => [
        'enabled' => env('OTEL_LOGS_ENABLED', true),
        'exporter' => env('OTEL_LOGS_EXPORTER', 'otlp'),
    ],

    /*
    |--------------------------------------------------------------------------
    | Resource Attributes
    |--------------------------------------------------------------------------
    |
    | Additional resource attributes to be included with telemetry data.
    |
    */

    'resource_attributes' => [
        'deployment.environment' => env('APP_ENV', 'production'),
        'service.namespace' => env('OTEL_SERVICE_NAMESPACE', 'laravel'),
        'service.instance.id' => env('OTEL_SERVICE_INSTANCE_ID', gethostname()),
    ],

    /*
    |--------------------------------------------------------------------------
    | AWS X-Ray Specific Configuration
    |--------------------------------------------------------------------------
    |
    | Configuration specific to AWS X-Ray when used in production.
    |
    */

    'xray' => [
        'enabled' => env('OTEL_XRAY_ENABLED', false),
        'daemon_address' => env('OTEL_XRAY_DAEMON_ADDRESS', '127.0.0.1:2000'),
        'region' => env('AWS_DEFAULT_REGION', 'us-east-1'),
    ],
];