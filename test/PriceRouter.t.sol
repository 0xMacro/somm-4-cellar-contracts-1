// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { ERC20 } from "src/base/ERC20.sol";
import { IChainlinkAggregator } from "src/interfaces/external/IChainlinkAggregator.sol";
import { ICurveFi } from "src/interfaces/external/ICurveFi.sol";
import { ICurvePool } from "src/interfaces/external/ICurvePool.sol";
import { IPool } from "src/interfaces/external/IPool.sol";
import { MockGasFeed } from "src/mocks/MockGasFeed.sol";
import { PriceRouter } from "src/modules/price-router/PriceRouter.sol";
import { IUniswapV2Router02 as IUniswapV2Router } from "src/interfaces/external/IUniswapV2Router02.sol";

import { Test, console, stdStorage, StdStorage } from "@forge-std/Test.sol";
import { Math } from "src/utils/Math.sol";

contract PriceRouterTest is Test {
    using Math for uint256;
    using stdStorage for StdStorage;

    event AddAsset(address indexed asset);
    event RemoveAsset(address indexed asset);

    PriceRouter private immutable priceRouter = new PriceRouter();

    address private immutable sender = vm.addr(0xABCD);
    address private immutable receiver = vm.addr(0xBEEF);

    // Valid Derivatives
    uint8 private constant CHAINLINK_DERIVATIVE = 1;
    uint8 private constant CURVE_DERIVATIVE = 2;
    uint8 private constant CURVEV2_DERIVATIVE = 3;
    uint8 private constant AAVE_DERIVATIVE = 4;

    // Mainnet contracts:
    ERC20 private constant WETH = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 private constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 private constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 private constant WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 private constant BOND = ERC20(0x0391D2021f89DC339F60Fff84546EA23E337750f);
    ERC20 private constant USDT = ERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    ERC20 private constant FRAX = ERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IUniswapV2Router private constant uniV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    // Aave assets.
    ERC20 private constant aDAI = ERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    ERC20 private constant aUSDC = ERC20(0xBcca60bB61934080951369a648Fb03DF4F96263C);
    ERC20 private constant aUSDT = ERC20(0x3Ed3B47Dd13EC9a98b44e6204A523E766B225811);

    // Curve Pools and Tokens.
    address private constant TriCryptoPool = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    ERC20 private constant CRV_3_CRYPTO = ERC20(0xc4AD29ba4B3c580e6D59105FFf484999997675Ff);
    address private constant daiUsdcUsdtPool = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    ERC20 private constant CRV_DAI_USDC_USDT = ERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    address private constant frax3CrvPool = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    ERC20 private constant CRV_FRAX_3CRV = ERC20(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address private constant wethCrvPool = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    ERC20 private constant CRV_WETH_CRV = ERC20(0xEd4064f376cB8d68F770FB1Ff088a3d0F3FF5c4d);
    address private constant aave3Pool = 0xDeBF20617708857ebe4F679508E7b7863a8A8EeE;
    ERC20 private constant CRV_AAVE_3CRV = ERC20(0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900);

    address public automationRegistry = 0x02777053d6764996e594c3E88AF1D58D5363a2e6;

    // Chainlink PriceFeeds
    address private WETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address private DAI_USD_FEED = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
    address private WBTC_USD_FEED = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    address private USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address private BOND_ETH_FEED = 0xdd22A54e05410D8d1007c38b5c7A3eD74b855281;
    address private FRAX_USD_FEED = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;
    address private ETH_FAST_GAS_FEED = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() external {
        // Ignore if not on mainnet.
        if (block.chainid != 1) return;

        PriceRouter.ChainlinkDerivativeStorage memory stor;

        PriceRouter.AssetSettings memory settings;

        uint256 price = uint256(IChainlinkAggregator(WETH_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, DAI_USD_FEED);
        priceRouter.addAsset(DAI, settings, abi.encode(stor), 1e8);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);

        price = uint256(IChainlinkAggregator(WBTC_USD_FEED).latestAnswer());
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WBTC_USD_FEED);
        priceRouter.addAsset(WBTC, settings, abi.encode(stor), price);

        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        priceRouter.addAsset(BOND, settings, abi.encode(stor), 2.673e8);
    }

    // ======================================= ASSET TESTS =======================================
    function testAddChainlinkAsset() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            100e18,
            0.0001e18,
            2 days,
            true
        );

        priceRouter.addAsset(BOND, settings, abi.encode(stor), 2.673e8);

        (uint144 maxPrice, uint80 minPrice, uint24 heartbeat, bool isETH) = priceRouter.getChainlinkDerivativeStorage(
            BOND
        );

        assertTrue(isETH, "BOND data feed should be in ETH");
        assertEq(minPrice, 0.0001e18, "Should set min price");
        assertEq(maxPrice, 100e18, "Should set max price");
        assertEq(heartbeat, 2 days, "Should set heartbeat");
        assertTrue(priceRouter.isSupported(BOND), "Asset should be supported");
    }

    function testAddCurveAsset() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
        uint256 vp = ICurvePool(TriCryptoPool).get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 883.56e8);

        (uint96 datum, uint64 timeLastUpdated, uint32 posDelta, uint32 negDelta, uint32 rateLimit) = priceRouter
            .getVirtualPriceBound(address(CRV_3_CRYPTO));

        assertEq(datum, vp, "`datum` should equal the virtual price.");
        assertEq(timeLastUpdated, block.timestamp, "`timeLastUpdated` should equal current timestamp.");
        assertEq(posDelta, 1.01e8, "`posDelta` should equal 1.01.");
        assertEq(negDelta, 0.99e8, "`negDelta` should equal 0.99.");
        assertEq(rateLimit, priceRouter.DEFAULT_RATE_LIMIT(), "`rateLimit` should have been set to default.");
    }

    function testMinPriceGreaterThanMaxPrice() external {
        // Make sure adding an asset with an invalid price range fails.
        uint80 minPrice = 2e8;
        uint144 maxPrice = 1e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            maxPrice,
            minPrice,
            2 days,
            false
        );

        vm.expectRevert(
            abi.encodeWithSelector(PriceRouter.PriceRouter__MinPriceGreaterThanMaxPrice.selector, minPrice, maxPrice)
        );
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAddInvalidAsset() external {
        PriceRouter.AssetSettings memory settings;
        vm.expectRevert(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidAsset.selector, address(0)));
        priceRouter.addAsset(ERC20(address(0)), settings, abi.encode(0), 0);
    }

    function testAddAssetEmit() external {
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDT_USD_FEED);
        vm.expectEmit(true, false, false, false);
        emit AddAsset(address(USDT));
        priceRouter.addAsset(USDT, settings, abi.encode(stor), 1e8);
    }

    function testAddAssetWithInvalidMinPrice() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 1, 0, false);
        vm.expectRevert(bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidMinPrice.selector, 1, 1100000)));
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAddAssetWithInvalidMaxPrice() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            999e18,
            0,
            0,
            false
        );
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__InvalidMaxPrice.selector, 999e18, 90000000000))
        );
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    /**
     * @notice All pricing operations go through `_getValueInUSD`, so checking for revert in `addAsset` is sufficient.
     */
    function testAssetBelowMinPrice() external {
        // Store price of USDC.
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());

        // Add USDC again, but set a bad minPrice.
        uint80 badMinPrice = 1.1e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            0,
            badMinPrice,
            0,
            false
        );
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__AssetBelowMinPrice.selector,
                    address(USDC),
                    price,
                    badMinPrice
                )
            )
        );
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    /**
     * @notice All pricing operations go through `_getValueInUSD`, so checking for revert in `addAsset` is sufficient.
     */
    function testAssetAboveMaxPrice() external {
        // Store price of USDC.
        uint256 price = uint256(IChainlinkAggregator(USDC_USD_FEED).latestAnswer());

        // Add USDC again, but set a bad maxPrice.
        uint144 badMaxPrice = 0.9e8;
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, USDC_USD_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            badMaxPrice,
            0,
            0,
            false
        );
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__AssetAboveMaxPrice.selector,
                    address(USDC),
                    price,
                    badMaxPrice
                )
            )
        );
        priceRouter.addAsset(USDC, settings, abi.encode(stor), 1e8);
    }

    function testAssetStalePrice() external {
        // Store timestamp of USDC.
        uint256 timestamp = uint256(IChainlinkAggregator(USDC_USD_FEED).latestTimestamp());
        timestamp = block.timestamp - timestamp;

        // Advance time so that the price becomes stale.
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__StalePrice.selector,
                    address(USDC),
                    timestamp + 1 days,
                    1 days
                )
            )
        );
        priceRouter.getValue(USDC, 1e6, USDC);
    }

    function testETHtoUSDPriceFeedIsChecked() external {
        // Check if querying an asset that needs the ETH to USD price feed, that the feed is checked.
        // Add BOND as an asset.
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(
            100e18,
            0.0001e18,
            2 days,
            true
        );

        priceRouter.addAsset(BOND, settings, abi.encode(stor), 2.673e8);

        // Re-add WETH, but shorten the heartbeat.
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, WETH_USD_FEED);
        stor = PriceRouter.ChainlinkDerivativeStorage(0, 0.0, 3600, false);
        priceRouter.addAsset(WETH, settings, abi.encode(stor), 1_112e8);

        uint256 timestamp = uint256(IChainlinkAggregator(WETH_USD_FEED).latestTimestamp());
        timestamp = block.timestamp - timestamp;

        // Advance time forward such that the ETH USD price feed is stale, but the BOND ETH price feed is not.
        vm.warp(block.timestamp + 3600);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__StalePrice.selector,
                    address(WETH),
                    timestamp + 3600,
                    3600
                )
            )
        );
        priceRouter.getValue(BOND, 1e18, USDC);
    }

    // ======================================= PRICING TESTS =======================================

    function testExchangeRate() external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        priceRouter.addAsset(BOND, settings, abi.encode(stor), 2.673e8);
        uint256 exchangeRate;

        // Test exchange rates work when quote is same as base.
        exchangeRate = priceRouter.getExchangeRate(USDC, USDC);
        assertEq(exchangeRate, 1e6, "USDC -> USDC Exchange Rate Should be 1e6");

        exchangeRate = priceRouter.getExchangeRate(DAI, DAI);
        assertEq(exchangeRate, 1e18, "DAI -> DAI Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WETH, WETH);
        assertEq(exchangeRate, 1e18, "WETH -> WETH Exchange Rate Should be 1e18");

        exchangeRate = priceRouter.getExchangeRate(WBTC, WBTC);
        assertEq(exchangeRate, 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");

        exchangeRate = priceRouter.getExchangeRate(BOND, BOND); // Weird asset with an ETH price but no USD price.
        assertEq(exchangeRate, 1e18, "BOND -> BOND Exchange Rate Should be 1e18");

        // // Test exchange rates.
        address[] memory path = new address[](2);
        path[0] = address(DAI);
        path[1] = address(USDC);
        uint256[] memory amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(DAI, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "DAI -> USDC Exchange Rate Should be 1 +- 1% USDC");

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, WBTC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> WBTC Exchange Rate Should be 0.5ish +- 1% WBTC");

        path[0] = address(WETH);
        path[1] = address(USDC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        exchangeRate = priceRouter.getExchangeRate(WETH, USDC);
        assertApproxEqRel(exchangeRate, amounts[1], 1e16, "WETH -> USDC Exchange Rate Failure");

        path[0] = address(USDC);
        path[1] = address(BOND);
        amounts = uniV2Router.getAmountsOut(1e6, path);

        exchangeRate = priceRouter.getExchangeRate(USDC, BOND);
        assertApproxEqRel(exchangeRate, amounts[1], 0.02e18, "USDC -> BOND Exchange Rate Failure");

        ERC20[] memory baseAssets = new ERC20[](5);
        baseAssets[0] = USDC;
        baseAssets[1] = DAI;
        baseAssets[2] = WETH;
        baseAssets[3] = WBTC;
        baseAssets[4] = BOND;

        uint256[] memory exchangeRates = priceRouter.getExchangeRates(baseAssets, WBTC);

        path[0] = address(WETH);
        path[1] = address(WBTC);
        amounts = uniV2Router.getAmountsOut(1e18, path);

        assertApproxEqRel(exchangeRates[2], amounts[1], 1e16, "WBTC exchangeRates failed against WETH");

        assertEq(exchangeRates[3], 1e8, "WBTC -> WBTC Exchange Rate Should be 1e8");
    }

    function testGetValue(
        uint256 assets0,
        uint256 assets1,
        uint256 assets2
    ) external {
        PriceRouter.AssetSettings memory settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, BOND_ETH_FEED);
        PriceRouter.ChainlinkDerivativeStorage memory stor = PriceRouter.ChainlinkDerivativeStorage(0, 0, 0, true);

        priceRouter.addAsset(BOND, settings, abi.encode(stor), 2.673e8);

        // Check if `getValues` reverts if assets array and amount array lengths differ
        ERC20[] memory baseAssets = new ERC20[](3);
        uint256[] memory amounts = new uint256[](2);
        vm.expectRevert(PriceRouter.PriceRouter__LengthMismatch.selector);
        priceRouter.getValues(baseAssets, amounts, USDC);

        assets0 = bound(assets0, 1e6, type(uint72).max);
        assets1 = bound(assets1, 1e18, type(uint112).max);
        assets2 = bound(assets2, 1e8, type(uint48).max);

        baseAssets = new ERC20[](3);
        baseAssets[0] = USDC;
        baseAssets[1] = BOND;
        baseAssets[2] = WBTC;

        amounts = new uint256[](3);
        amounts[0] = assets0;
        amounts[1] = assets1;
        amounts[2] = assets2;

        uint256 totalValue = priceRouter.getValues(baseAssets, amounts, USDC);

        // Find the value using uniswap.

        uint256 sum = assets0; // Since the first one is USDC, no conversion is needed.

        address[] memory path = new address[](2);
        path[0] = address(BOND);
        path[1] = address(USDC);
        uint256[] memory amountsOut = uniV2Router.getAmountsOut(1e18, path);
        sum += (amountsOut[1] * assets1) / 1e18;

        path[0] = address(WBTC);
        path[1] = address(USDC);
        amountsOut = uniV2Router.getAmountsOut(1e4, path);
        sum += (amountsOut[1] * assets2) / 1e4;

        // Most tests use a 1% price difference between Chainlink and Uniswap, but WBTC value
        // derived from Uniswap is significantly off from historical values, while the value
        // calculated by the price router is much more accurate.
        assertApproxEqRel(
            totalValue,
            sum,
            0.05e18,
            "Total Value of USDC, BOND, and WBTC outside of 10% envelope with UniV2"
        );
    }

    function testUnsupportedAsset() external {
        ERC20 LINK = ERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA);

        // Check that price router `getValue` reverts if the base asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValue(LINK, 0, WETH);

        // Check that price router `getValue` reverts if the quote asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValue(WETH, 0, LINK);

        ERC20[] memory assets = new ERC20[](1);
        uint256[] memory amounts = new uint256[](1);

        // Check that price router `getValues` reverts if the base asset is not supported.
        assets[0] = LINK;
        amounts[0] = 1; // If amount is zero, getValues skips pricing the asset.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValues(assets, amounts, WETH);

        // Check that price router `getValues` reverts if the quote asset is not supported.
        assets[0] = WETH;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getValues(assets, amounts, LINK);

        // Check that price router `getExchange` reverts if the base asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRate(LINK, WETH);

        // Check that price router `getExchangeRate` reverts if the quote asset is not supported.
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRate(WETH, LINK);

        // Check that price router `getExchangeRates` reverts if the base asset is not supported.
        assets[0] = LINK;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRates(assets, WETH);

        // Check that price router `getExchangeRates` reverts if the quote asset is not supported.
        assets[0] = WETH;
        vm.expectRevert(
            bytes(abi.encodeWithSelector(PriceRouter.PriceRouter__UnsupportedAsset.selector, address(LINK)))
        );
        priceRouter.getExchangeRates(assets, LINK);
    }

    // ======================================= CURVEv1 TESTS =======================================
    function testCRV3Pool() external {
        // Add 3Pool to price router.
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(1.0224e8),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

        // Start by adding liquidity to 3Pool.
        uint256 amount = 1_000e18;
        deal(address(DAI), address(this), amount);
        DAI.approve(daiUsdcUsdtPool, amount);
        ICurveFi pool = ICurveFi(daiUsdcUsdtPool);
        uint256[3] memory amounts = [amount, 0, 0];
        pool.add_liquidity(amounts, 0);
        uint256 lpReceived = CRV_DAI_USDC_USDT.balanceOf(address(this));
        uint256 inputAmountWorth = priceRouter.getValue(DAI, amount, USDC);
        uint256 outputAmountWorth = priceRouter.getValue(CRV_DAI_USDC_USDT, lpReceived, USDC);
        assertApproxEqRel(
            outputAmountWorth,
            inputAmountWorth,
            0.01e18,
            "3CRV LP tokens should be worth DAI input +- 1%"
        );
    }

    function testCRVFrax3Pool() external {
        // Add 3Pool to price router.
        PriceRouter.AssetSettings memory settings;
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
        ICurveFi pool = ICurveFi(daiUsdcUsdtPool);
        uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

        // Add FRAX to price router.
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

        // Add FRAX3CRV to price router.
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
        pool = ICurveFi(frax3CrvPool);
        vp = pool.get_virtual_price().changeDecimals(18, 8);
        vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
        priceRouter.addAsset(CRV_FRAX_3CRV, settings, abi.encode(vpBound), 1.0087e8);

        // Add liquidity to Frax 3CRV Pool.
        uint256 amount = 1_000e18;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
        deal(address(FRAX), address(this), amount);
        FRAX.approve(frax3CrvPool, amount);
        uint256[2] memory amounts = [amount, 0];
        pool.add_liquidity(amounts, 0);
        uint256 lpReceived = CRV_FRAX_3CRV.balanceOf(address(this));
        uint256 inputAmountWorth = priceRouter.getValue(FRAX, amount, USDC);
        uint256 outputAmountWorth = priceRouter.getValue(CRV_FRAX_3CRV, lpReceived, USDC);
        assertApproxEqRel(
            outputAmountWorth,
            inputAmountWorth,
            0.01e18,
            "Frax 3CRV LP tokens should be worth FRAX input +- 1%"
        );
    }

    function testCRVAave3Pool() external {
        // Add aDAI to the price router.
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aDAI));
        priceRouter.addAsset(aDAI, settings, abi.encode(0), 1e8);

        // Add aUSDC to the price router.
        settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aUSDC));
        priceRouter.addAsset(aUSDC, settings, abi.encode(0), 1e8);

        // Add aUSDT to the price router.
        settings = PriceRouter.AssetSettings(AAVE_DERIVATIVE, address(aUSDT));
        priceRouter.addAsset(aUSDT, settings, abi.encode(0), 1e8);

        // Add Aave 3Pool.
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, aave3Pool);
        uint256 vp = ICurvePool(aave3Pool).get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_AAVE_3CRV, settings, abi.encode(vpBound), 1.0983e8);

        // Add liquidity to Aave 3 Pool.
        uint256 amount = 1_000e18;
        deal(address(DAI), address(this), amount);
        IPool aavePool = IPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        DAI.approve(address(aavePool), amount);
        aavePool.deposit(address(DAI), amount, address(this), 0);
        amount = aDAI.balanceOf(address(this));
        aDAI.approve(aave3Pool, amount);
        ICurveFi pool = ICurveFi(aave3Pool);
        uint256[3] memory amounts = [amount, 0, 0];
        pool.add_liquidity(amounts, 0);
        uint256 lpReceived = CRV_AAVE_3CRV.balanceOf(address(this));

        // Check value in vs value out.
        uint256 inputAmountWorth = priceRouter.getValue(aDAI, amount, USDC);
        uint256 outputAmountWorth = priceRouter.getValue(CRV_AAVE_3CRV, lpReceived, USDC);
        assertApproxEqRel(
            outputAmountWorth,
            inputAmountWorth,
            0.01e18,
            "Aave 3 Pool LP tokens should be worth aDAI input +- 1%"
        );
    }

    function testCurveV1VirtualPriceBoundsCheck() external {
        // Add 3Pool to price router.
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(1.0224e8),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

        // Change virtual price to move it above upper bound.
        _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.90e18);
        uint256 currentVirtualPrice = ICurvePool(daiUsdcUsdtPool).get_virtual_price();
        (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
        uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
                    currentVirtualPrice,
                    upper
                )
            )
        );
        priceRouter.getValue(CRV_DAI_USDC_USDT, 1e18, USDC);

        // Change virtual price to move it below lower bound.
        _adjustVirtualPrice(CRV_DAI_USDC_USDT, 1.20e18);
        currentVirtualPrice = ICurvePool(daiUsdcUsdtPool).get_virtual_price();
        uint256 lower = uint256(datum).mulDivDown(0.99e8, 1e8).changeDecimals(8, 18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentBelowLowerBound.selector,
                    currentVirtualPrice,
                    lower
                )
            )
        );
        priceRouter.getValue(CRV_DAI_USDC_USDT, 1e18, USDC);
    }

    // ======================================= CURVEv2 TESTS =======================================
    function testCRV3Crypto() external {
        // Add 3Crypto to the price router
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(1.0248e8),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 883.56e8);

        // Start by adding liquidity to 3CRVCrypto.
        uint256 amount = 10e18;
        deal(address(WETH), address(this), amount);
        WETH.approve(TriCryptoPool, amount);
        ICurveFi pool = ICurveFi(TriCryptoPool);
        uint256[3] memory amounts = [0, 0, amount];
        pool.add_liquidity(amounts, 0);
        uint256 lpReceived = CRV_3_CRYPTO.balanceOf(address(this));
        uint256 inputAmountWorth = priceRouter.getValue(WETH, amount, USDC);
        uint256 outputAmountWorth = priceRouter.getValue(CRV_3_CRYPTO, lpReceived, USDC);
        assertApproxEqRel(
            outputAmountWorth,
            inputAmountWorth,
            0.01e18,
            "TriCrypto LP tokens should be worth WETH input +- 1%"
        );
    }

    function testCRVWETHCRVPool() external {
        // Add WETH CRV Pool to the price router
        ICurveFi pool = ICurveFi(wethCrvPool);
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
        uint256 price = priceRouter.getValue(WETH, 0.051699e18, USDC);
        uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), price.changeDecimals(6, 8));

        // Start by adding liquidity to WETH CRV Pool.
        uint256 amount = 10e18;
        deal(address(WETH), address(this), amount);
        WETH.approve(wethCrvPool, amount);
        uint256[2] memory amounts = [amount, 0];
        pool.add_liquidity(amounts, 0);
        uint256 lpReceived = CRV_WETH_CRV.balanceOf(address(this));
        uint256 inputAmountWorth = priceRouter.getValue(WETH, amount, USDC);
        uint256 outputAmountWorth = priceRouter.getValue(CRV_WETH_CRV, lpReceived, USDC);
        assertApproxEqRel(
            outputAmountWorth,
            inputAmountWorth,
            0.01e18,
            "WETH CRV LP tokens should be worth WETH input +- 1%"
        );
    }

    function testCurveV2VirtualPriceBoundsCheck() external {
        // Add WETH CRV Pool to the price router
        ICurveFi pool = ICurveFi(wethCrvPool);
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
        uint256 price = priceRouter.getValue(WETH, 0.051699e18, USDC);
        uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), price.changeDecimals(6, 8));

        // Change virtual price to move it above upper bound.
        _adjustVirtualPrice(CRV_WETH_CRV, 0.90e18);
        uint256 currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
        (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
        uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
                    currentVirtualPrice,
                    upper
                )
            )
        );
        priceRouter.getValue(CRV_WETH_CRV, 1e18, USDC);

        // Change virtual price to move it below lower bound.
        _adjustVirtualPrice(CRV_WETH_CRV, 1.20e18);
        currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
        uint256 lower = uint256(datum).mulDivDown(0.99e8, 1e8).changeDecimals(8, 18);

        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentBelowLowerBound.selector,
                    currentVirtualPrice,
                    lower
                )
            )
        );
        priceRouter.getValue(CRV_WETH_CRV, 1e18, USDC);
    }

    // ======================================= AUTOMATION TESTS =======================================
    function testAutomationLogic() external {
        // Set up price router to use mock gas feed.
        MockGasFeed gasFeed = new MockGasFeed();
        priceRouter.setGasFeed(address(gasFeed));

        gasFeed.setAnswer(30e9);

        // Add 3Pool to price router.
        ICurvePool pool = ICurvePool(daiUsdcUsdtPool);
        uint256 oldVirtualPrice = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(oldVirtualPrice),
            0,
            uint32(1.001e8),
            uint32(0.999e8),
            0
        );
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);
        (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
            abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
        );
        assertTrue(!upkeepNeeded, "Upkeep should not be needed");
        // Increase the virtual price by about 0.10101%
        _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.999e18);
        vm.warp(block.timestamp + 1 days);
        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(upkeepNeeded, "Upkeep should be needed");

        // Simulate gas price spike.
        gasFeed.setAnswer(300e9);
        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed");

        // Gas recovers to a normal level.
        gasFeed.setAnswer(30e9);
        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(upkeepNeeded, "Upkeep should be needed");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0)));
        (uint96 datum, uint64 timeLastUpdated, , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
        assertEq(datum, oldVirtualPrice.mulDivDown(1.001e8, 1e8), "Datum should equal old virtual price upper bound.");
        assertEq(timeLastUpdated, block.timestamp, "Time last updated should equal current timestamp.");

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed");

        // If enough time passes, and gas price becomes low enough, datum may be updated again.
        vm.warp(block.timestamp + 1 days);
        _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.9995e18);
        // With adjusted virtual price new max gas limit should be just over 25 gwei.
        gasFeed.setAnswer(25e9);
        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(upkeepNeeded, "Upkeep should be needed");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
        (datum, timeLastUpdated, , , ) = priceRouter.getVirtualPriceBound(address(CRV_DAI_USDC_USDT));
        assertEq(datum, pool.get_virtual_price().changeDecimals(18, 8), "Datum should equal virtual price.");
        assertEq(timeLastUpdated, block.timestamp, "Time last updated should equal current timestamp.");
    }

    function testUpkeepPriority() external {
        // Add WETH CRV Pool to the price router
        ICurveFi pool = ICurveFi(wethCrvPool);
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
        uint256 price = priceRouter.getValue(WETH, 0.051699e18, USDC);
        uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            0
        );
        priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), price.changeDecimals(6, 8));

        // Add 3Crypto to the price router
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, TriCryptoPool);
        vpBound = PriceRouter.VirtualPriceBound(uint96(1.0248e8), 0, uint32(1.01e8), uint32(0.99e8), 0);
        priceRouter.addAsset(CRV_3_CRYPTO, settings, abi.encode(vpBound), 883.56e8);

        // Add 3Pool to price router.
        PriceRouter.ChainlinkDerivativeStorage memory stor;
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, daiUsdcUsdtPool);
        pool = ICurveFi(daiUsdcUsdtPool);
        vp = pool.get_virtual_price().changeDecimals(18, 8);
        vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
        priceRouter.addAsset(CRV_DAI_USDC_USDT, settings, abi.encode(vpBound), 1.0224e8);

        // Add FRAX to price router.
        settings = PriceRouter.AssetSettings(CHAINLINK_DERIVATIVE, FRAX_USD_FEED);
        priceRouter.addAsset(FRAX, settings, abi.encode(stor), 1e8);

        // Add FRAX3CRV to price router.
        settings = PriceRouter.AssetSettings(CURVE_DERIVATIVE, frax3CrvPool);
        pool = ICurveFi(frax3CrvPool);
        vp = pool.get_virtual_price().changeDecimals(18, 8);
        vpBound = PriceRouter.VirtualPriceBound(uint96(vp), 0, uint32(1.01e8), uint32(0.99e8), 0);
        priceRouter.addAsset(CRV_FRAX_3CRV, settings, abi.encode(vpBound), 1.0087e8);

        // Advance time to prevent rate limiting.
        vm.warp(block.timestamp + 1 days);

        // Adjust all Curve Assets virtual prices to make their deltas vary.
        _adjustVirtualPrice(CRV_WETH_CRV, 0.95e18);
        _adjustVirtualPrice(CRV_3_CRYPTO, 1.1e18);
        _adjustVirtualPrice(CRV_DAI_USDC_USDT, 0.85e18);
        _adjustVirtualPrice(CRV_FRAX_3CRV, 1.30e18);
        // Upkeep should prioritize upkeeps in the following order.
        // 1) CRV_FRAX_3CRV
        // 2) CRV_DAI_USDC_USDT
        // 3) CRV_3_CRYPTO
        // 4) CRV_WETH_CRV
        (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
            abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
        );
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        assertEq(abi.decode(performData, (uint256)), 3, "Upkeep should target index 3.");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        assertEq(abi.decode(performData, (uint256)), 2, "Upkeep should target index 2.");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        assertEq(abi.decode(performData, (uint256)), 1, "Upkeep should target index 1.");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

        // Passing in a 5 for the end index should still work.
        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 5)));
        assertTrue(upkeepNeeded, "Upkeep should be needed.");
        assertEq(abi.decode(performData, (uint256)), 0, "Upkeep should target index 0.");
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        assertTrue(!upkeepNeeded, "Upkeep should not be needed.");
    }

    function testRecoveringFromExtremeVirtualPriceMovements() external {
        // Add WETH CRV Pool to the price router
        ICurveFi pool = ICurveFi(wethCrvPool);
        PriceRouter.AssetSettings memory settings;
        settings = PriceRouter.AssetSettings(CURVEV2_DERIVATIVE, wethCrvPool);
        uint256 price = priceRouter.getValue(WETH, 0.051699e18, USDC);
        uint256 vp = pool.get_virtual_price().changeDecimals(18, 8);
        PriceRouter.VirtualPriceBound memory vpBound = PriceRouter.VirtualPriceBound(
            uint96(vp),
            0,
            uint32(1.01e8),
            uint32(0.99e8),
            1 days / 2
        );
        priceRouter.addAsset(CRV_WETH_CRV, settings, abi.encode(vpBound), price.changeDecimals(6, 8));

        vm.warp(block.timestamp + 1 days / 2);

        // Virtual price grows suddenly.
        _adjustVirtualPrice(CRV_WETH_CRV, 0.95e18);

        // Pricing calls now revert.
        uint256 currentVirtualPrice = ICurvePool(wethCrvPool).get_virtual_price();
        (uint96 datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
        uint256 upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
                    currentVirtualPrice,
                    upper
                )
            )
        );
        priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

        // Keepers adjust the virtual price, but pricing calls still revert.
        (bool upkeepNeeded, bytes memory performData) = priceRouter.checkUpkeep(
            abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0))
        );
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
        (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
        upper = uint256(datum).mulDivDown(1.01e8, 1e8).changeDecimals(8, 18);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
                    currentVirtualPrice,
                    upper
                )
            )
        );
        priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

        // At this point it will still take several days(because of rate limiting), for pricing calls to not revert.
        // The owner can do a couple different things.
        // Update the rate limit value to something smaller so there is less time between upkeeps.
        priceRouter.updateVirtualPriceBound(address(CRV_WETH_CRV), 1.01e8, 0.99e8, 1 days / 8);
        // Update the posDelta,a nd negDelta values so the virtual price can be updated more in each upkeep.
        // This method is discouraged because the wider the price range is the more susceptible this contract
        // is to Curve re-entrancy attacks.
        priceRouter.updateVirtualPriceBound(address(CRV_WETH_CRV), 1.02e8, 0.99e8, 1 days / 8);

        vm.warp(block.timestamp + 1 days / 8);

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        vm.prank(automationRegistry);
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
        (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
        upper = uint256(datum).mulDivDown(1.02e8, 1e8).changeDecimals(8, 18);
        vm.expectRevert(
            bytes(
                abi.encodeWithSelector(
                    PriceRouter.PriceRouter__CurrentAboveUpperBound.selector,
                    currentVirtualPrice,
                    upper
                )
            )
        );
        priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);

        vm.warp(block.timestamp + 1 days / 8);

        (upkeepNeeded, performData) = priceRouter.checkUpkeep(abi.encode(CURVE_DERIVATIVE, abi.encode(0, 0)));
        vm.prank(automationRegistry);
        uint256 gas = gasleft();
        priceRouter.performUpkeep(abi.encode(CURVE_DERIVATIVE, performData));
        console.log("Gas used", gas - gasleft());
        // Virtual price is now back within logical bounds so pricing operations work as expected.
        priceRouter.getValue(CRV_WETH_CRV, 1e18, WETH);
        (datum, , , , ) = priceRouter.getVirtualPriceBound(address(CRV_WETH_CRV));
        upper = uint256(datum).mulDivDown(1.02e8, 1e8).changeDecimals(8, 18);
        console.log("VP", currentVirtualPrice);
        console.log("Upper", upper);
    }

    // ======================================= INTEGRATION TESTS =======================================
    function testCRVAttackVector() external {
        address SiloFraxPool = 0x9a22CDB1CA1cdd2371cD5BB5199564C4E89465eb;
        ERC20 SILO = ERC20(0x6f80310CA7F2C654691D1383149Fa1A57d8AB1f8);

        uint256 amount = 10_000_000e18;
        deal(address(FRAX), address(this), amount);
        FRAX.approve(SiloFraxPool, amount);

        ICurvePool pool = ICurvePool(SiloFraxPool);
        uint256 virtualPriceBefore = pool.get_virtual_price();
        uint256 lpPriceBefore = pool.lp_price();
        uint256 priceOracleBefore = pool.price_oracle();
        ICurveFi(SiloFraxPool).exchange(1, 0, amount, 0, false);
        uint256 virtualPriceAfter = pool.get_virtual_price();
        uint256 lpPriceAfter = pool.lp_price();
        uint256 priceOracleAfter = pool.price_oracle();
        // console.log("Results from swapping 10M FRAX to SILO");
        // console.log("Virtual Price Before:", virtualPriceBefore);
        // console.log("Virtual Price After: ", virtualPriceAfter);
        // console.log("LP Price Before:     ", lpPriceBefore);
        // console.log("LP Price After:      ", lpPriceAfter);
        // console.log("Price Oracle Before: ", priceOracleBefore);
        // console.log("Price Oracle After:  ", priceOracleAfter);

        virtualPriceBefore = pool.get_virtual_price();
        lpPriceBefore = pool.lp_price();
        priceOracleBefore = pool.price_oracle();
        SILO.approve(SiloFraxPool, type(uint256).max);
        uint256 siloBalance = SILO.balanceOf(address(this));
        ICurveFi(SiloFraxPool).exchange(0, 1, siloBalance, 0, false);
        virtualPriceAfter = pool.get_virtual_price();
        lpPriceAfter = pool.lp_price();
        priceOracleAfter = pool.price_oracle();
        // console.log("Results from swapping SILO balance to FRAX");
        // console.log("Virtual Price Before:", virtualPriceBefore);
        // console.log("Virtual Price After: ", virtualPriceAfter);
        // console.log("LP Price Before:     ", lpPriceBefore);
        // console.log("LP Price After:      ", lpPriceAfter);
        // console.log("Price Oracle Before: ", priceOracleBefore);
        // console.log("Price Oracle After:  ", priceOracleAfter);

        // console.log("FRAX Remaining:", FRAX.balanceOf(address(this)));
        // console.log("FRAX Lost: (-)", amount - FRAX.balanceOf(address(this)));
        siloBalance = SILO.balanceOf(address(this));
    }

    // ======================================= HELPER FUNCTIONS =======================================
    function _adjustVirtualPrice(ERC20 token, uint256 multiplier) internal {
        uint256 targetSupply = token.totalSupply().mulDivDown(multiplier, 1e18);
        stdstore.target(address(token)).sig("totalSupply()").checked_write(targetSupply);
    }
}
