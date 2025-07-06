<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use OpenTelemetry\API\Trace\TracerInterface;
use App\Models\Item;

class TestOpenTelemetry extends Command
{
    /**
     * The name and signature of the console command.
     *
     * @var string
     */
    protected $signature = 'otel:test';

    /**
     * The console command description.
     *
     * @var string
     */
    protected $description = 'Test OpenTelemetry integration by performing various operations';

    private TracerInterface $tracer;

    public function __construct(TracerInterface $tracer)
    {
        parent::__construct();
        $this->tracer = $tracer;
    }

    /**
     * Execute the console command.
     */
    public function handle()
    {
        $this->info('Testing OpenTelemetry integration...');

        $span = $this->tracer->spanBuilder('otel.test.command')
            ->startSpan();

        $scope = $span->activate();

        try {
            // Test database operations
            $this->testDatabaseOperations();

            // Test logging
            $this->testLogging();

            $this->info('OpenTelemetry test completed successfully!');
            $this->info('Check your OpenTelemetry collector output for traces.');
        } catch (\Throwable $e) {
            $span->recordException($e);
            $span->setStatus(\OpenTelemetry\API\Trace\StatusCode::STATUS_ERROR, $e->getMessage());
            $this->error('Test failed: ' . $e->getMessage());
        } finally {
            $span->end();
            $scope->detach();
        }
    }

    private function testDatabaseOperations()
    {
        $dbSpan = $this->tracer->spanBuilder('otel.test.database')
            ->startSpan();

        $dbScope = $dbSpan->activate();

        try {
            $this->info('Testing database operations...');

            // Create
            $item = Item::create([
                'name' => 'Test Item',
                'description' => 'This is a test item for OpenTelemetry',
                'price' => 99.99,
                'quantity' => 10,
            ]);
            $this->info('Created item: ' . $item->id);

            // Read
            $items = Item::all();
            $this->info('Total items: ' . $items->count());

            // Update
            $item->update(['quantity' => 20]);
            $this->info('Updated item quantity to 20');

            // Delete
            $item->delete();
            $this->info('Deleted test item');

        } finally {
            $dbSpan->end();
            $dbScope->detach();
        }
    }

    private function testLogging()
    {
        $logSpan = $this->tracer->spanBuilder('otel.test.logging')
            ->startSpan();

        $logScope = $logSpan->activate();

        try {
            $this->info('Testing logging...');

            \Log::info('OpenTelemetry test info message', ['test' => true]);
            \Log::warning('OpenTelemetry test warning message', ['level' => 'warning']);
            \Log::error('OpenTelemetry test error message', ['error' => 'test']);

            $this->info('Logging tests completed');
        } finally {
            $logSpan->end();
            $logScope->detach();
        }
    }
}