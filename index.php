<?php

declare(strict_types=1);

use Symfony\Bundle\FrameworkBundle\Kernel\MicroKernelTrait;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpKernel\Attribute\MapQueryString;
use Symfony\Component\HttpKernel\Kernel as BaseKernel;
use Symfony\Component\Routing\Attribute\Route;

require __DIR__ . '/vendor/autoload_runtime.php';

require_once 'HelloQuery.php';

class Kernel extends BaseKernel
{
    use MicroKernelTrait;

    #[Route('/', name: 'home')]
    public function __invoke(
        #[MapQueryString]
        HelloQuery $query
    ): JsonResponse
    {
        return new JsonResponse([
            'hello' => $query->hello,
        ]);
    }
}


return static function (array $context) {
    return new Kernel($context['APP_ENV'], (bool)$context['APP_DEBUG']);
};
