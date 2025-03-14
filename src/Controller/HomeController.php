<?php

namespace App\Controller;

use App\Query\HelloQuery;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\Routing\Attribute\Route;
use Symfony\Component\HttpKernel\Attribute\MapQueryString;

class HomeController
{
    #[Route('/test', name: 'home')]
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