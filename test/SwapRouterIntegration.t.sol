// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { Registry } from "src/Registry.sol";
import { ICellarV1_5 as Cellar } from "src/interfaces/ICellarV1_5.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SwapRouter, IUniswapV2Router, IUniswapV3Router } from "src/modules/swap-router/SwapRouter.sol";
import { ICellarRouterV1_5 as CellarRouter } from "src/interfaces/ICellarRouterV1_5.sol";

import { Test, console } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract SwapRouterIntegrationTest is Test {
    ERC20 private USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address private gravityBridge = 0x69592e6f9d21989a043646fE8225da2600e5A0f7;
    address private sommMultiSig = 0x7340D1FeCD4B64A4ac34f826B21c945d44d7407F;
    address private strategist = 0x13FBB7e817e5347ce4ae39c3dff1E6705746DCdC;

    address private uniswapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private zeroXExchangeProxy = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    Cellar private cellarTrend;
    Cellar private cellarMomentum;
    Registry private registry;
    SwapRouter private swapRouter;
    CellarRouter private cellarRouter;

    function setUp() external {
        if (block.number < 15869436) {
            console.log("INVALID BLOCK NUMBER: Contracts not deployed yet use 15869436.");
        }
        cellarTrend = Cellar(0x6b7f87279982d919Bbf85182DDeAB179B366D8f2);
        cellarMomentum = Cellar(0x6E2dAc3b9E9ADc0CbbaE2D0B9Fd81952a8D33872);
        cellarRouter = CellarRouter(0x1D90366B0154fBcB5101c06a39c25D26cB48e889);

        registry = Registry(0xDffa1443a72Fd3f4e935b93d0C3BFf8FE80cE083);

        swapRouter = new SwapRouter(
            IUniswapV2Router(uniswapV2Router),
            IUniswapV3Router(uniswapV3Router),
            zeroXExchangeProxy
        );

        vm.prank(sommMultiSig);
        registry.setAddress(1, address(swapRouter));
    }

    function testCellars() external {
        _testCellar(cellarTrend);
        _testCellar(cellarMomentum);
    }

    function _testCellar(Cellar cellar) internal {
        uint256 userAssets = 10_000e6;
        //  Have user deposit into Cellar
        uint256 currentTotalAssets = cellar.totalAssets();
        deal(address(USDC), address(this), userAssets);
        USDC.approve(address(cellar), userAssets);
        cellar.deposit(userAssets, address(this));
        assertEq(cellar.totalAssets(), currentTotalAssets + userAssets, "Total assets should equal 100,000 USDC.");
        // Use the Cellar Router to Deposit and Swap into the cellar.
        userAssets = 10_000e18;
        currentTotalAssets = cellar.totalAssets();
        deal(address(DAI), address(this), userAssets);
        DAI.approve(address(cellarRouter), userAssets);
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint24[] memory poolFees = new uint24[](1);
        poolFees[0] = 100; // 0.01%
        bytes memory swapData = abi.encode(uint8(1), path, poolFees, userAssets, 0);
        cellarRouter.depositAndSwap(
            address(cellar),
            uint8(SwapRouter.Exchange.BASIC),
            swapData,
            userAssets,
            address(DAI)
        );
        currentTotalAssets = cellar.totalAssets();

        // Strategist swaps 10,000 USDC for wBTC on UniV3.
        vm.startPrank(gravityBridge);
        path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WBTC);
        poolFees = new uint24[](1);
        poolFees[0] = 3000; // 0.3% fee
        uint256 amount = 10_000e6;
        bytes memory params = abi.encode(uint8(1), path, poolFees, amount, 0);
        cellar.rebalance(address(USDC), address(WBTC), amount, uint8(0), params);
        vm.stopPrank();

        // Strategist swaps 10,000 USDC for wBTC on UniV2.
        vm.startPrank(gravityBridge);
        path = new address[](3);
        path[0] = address(USDC);
        path[1] = address(WETH);
        path[2] = address(WBTC);
        amount = 10_000e6;
        params = abi.encode(uint8(0), path, amount, 0);
        cellar.rebalance(address(USDC), address(WBTC), amount, uint8(0), params);
        vm.stopPrank();

        assertApproxEqRel(
            cellar.totalAssets(),
            currentTotalAssets,
            0.005e18,
            "Total assets should approximately be equal to 100,000 USDC."
        );

        // Have cellar rebalance using 0x.
        // API Query to get most recent data.
        //https://api.0x.org/swap/v1/quote?buyToken=WBTC&sellToken=USDC&sellAmount=10000000000
        address allowanceTarget = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
        uint256 assets = 10_000e6;
        bytes
            memory data = hex"6af479b2000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000002540be4000000000000000000000000000000000000000000000000000000000002e4067200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000042a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480001f4c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20001f42260fac5e5542a773aa44fbcfedf7c193bc2c599000000000000000000000000000000000000000000000000000000000000869584cd00000000000000000000000010000000000000000000000000000000000000110000000000000000000000000000000000000000000000fd53a464b263601c69";
        swapData = abi.encode(assets, allowanceTarget, allowanceTarget, data);
        vm.startPrank(gravityBridge);
        cellar.rebalance(address(USDC), address(WBTC), assets, uint8(1), swapData);
        vm.stopPrank();

        assertApproxEqRel(
            cellar.totalAssets(),
            currentTotalAssets,
            0.005e18,
            "Total assets should approximately be equal to 100,000 USDC."
        );
    }
}
