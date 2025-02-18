// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import { BaseAdaptor, ERC20, SafeTransferLib, Math, SwapRouter } from "src/modules/adaptors/BaseAdaptor.sol";
import { CErc20 } from "@compound/CErc20.sol";
import { ComptrollerG7 as Comptroller } from "@compound/ComptrollerG7.sol";

/**
 * @title Compound CToken Adaptor
 * @notice Allows Cellars to interact with Compound CToken positions.
 * @author crispymangoes
 */
contract CTokenAdaptor is BaseAdaptor {
    using SafeTransferLib for ERC20;
    using Math for uint256;

    //==================== Adaptor Data Specification ====================
    // adaptorData = abi.encode(address cToken)
    // Where:
    // `cToken` is the cToken address position this adaptor is working with
    //================= Configuration Data Specification =================
    // NOT USED
    // **************************** IMPORTANT ****************************
    // There is no way for a Cellar to take out loans on Compound, so there
    // are NO health factor checks done for `withdraw` or `withdrawableFrom`
    // In the future if a Compound debt adaptor is created, then this adaptor
    // must be changed to include some health factor checks like the
    // Aave aToken adaptor.
    //====================================================================

    //============================================ Global Functions ===========================================
    /**
     * @dev Identifier unique to this adaptor for a shared registry.
     * Normally the identifier would just be the address of this contract, but this
     * Identifier is needed during Cellar Delegate Call Operations, so getting the address
     * of the adaptor is more difficult.
     */
    function identifier() public pure override returns (bytes32) {
        return keccak256(abi.encode("Compound cToken Adaptor V 0.0"));
    }

    /**
     * @notice The Compound V2 Comptroller contract on Ethereum Mainnet.
     */
    function comptroller() internal pure returns (Comptroller) {
        return Comptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    }

    /**
     * @notice The COMP contract on Ethereum Mainnet.
     */
    function COMP() internal pure returns (ERC20) {
        return ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    }

    //============================================ Implement Base Functions ===========================================
    /**
     * @notice Cellar must approve market to spend its assets, then call mint to lend its assets.
     * @param assets the amount of assets to lend on Compound
     * @param adaptorData adaptor data containining the abi encoded cToken
     * @dev configurationData is NOT used
     */
    function deposit(
        uint256 assets,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Deposit assets to Aave.
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        ERC20 token = ERC20(cToken.underlying());
        token.safeApprove(address(cToken), assets);
        cToken.mint(assets);
    }

    /**
     @notice Cellars must withdraw from Compound.
     * @dev Important to verify that external receivers are allowed if receiver is not Cellar address.
     * @param assets the amount of assets to withdraw from Compound
     * @param receiver the address to send withdrawn assets to
     * @param adaptorData adaptor data containining the abi encoded cToken
     * @dev configurationData is NOT used
     * @dev There are NO health factor checks done in `withdraw`, or `withdrawableFrom`.
     *      If cellars ever take on Compound Debt it is crucial these checks are added,
     *      see "IMPORTANT" above.
     */
    function withdraw(
        uint256 assets,
        address receiver,
        bytes memory adaptorData,
        bytes memory
    ) public override {
        // Run external receiver check.
        _externalReceiverCheck(receiver);

        // Withdraw assets from Compound.
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        cToken.redeemUnderlying(assets);

        // Transfer assets to receiver.
        ERC20(cToken.underlying()).safeTransfer(receiver, assets);
    }

    /**
     * @notice Identical to `balanceOf`.
     * @dev There are NO health factor checks done in `withdraw`, or `withdrawableFrom`.
     *      If cellars ever take on Compound Debt it is crucial these checks are added,
     *      see "IMPORTANT" above.
     */
    function withdrawableFrom(bytes memory adaptorData, bytes memory) public view override returns (uint256) {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
    }

    /**
     * @notice Returns the cellars balance of the positions cToken underlying.
     * @dev Relies on `exchangeRateStored`, so if the stored exchange rate diverges
     *      from the current exchange rate, an arbitrage oppurtunity is created for
     *      people to enter the cellar right before the stored value is updated, then
     *      leave immediately after
     */
    function balanceOf(bytes memory adaptorData) public view override returns (uint256) {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        uint256 cTokenBalance = cToken.balanceOf(msg.sender);
        return cTokenBalance.mulDivDown(cToken.exchangeRateStored(), 1e18);
    }

    /**
     * @notice Returns the positions cToken underlying asset.
     */
    function assetOf(bytes memory adaptorData) public view override returns (ERC20) {
        CErc20 cToken = CErc20(abi.decode(adaptorData, (address)));
        return ERC20(cToken.underlying());
    }

    //============================================ Strategist Functions ===========================================
    /**
     * @notice Allows strategists to lend assets on Compound.
     * @dev Uses `_maxAvailable` helper function, see BaseAdaptor.sol
     * @param market the market to deposit to.
     * @param amountToDeposit the amount of `tokenToDeposit` to lend on Compound.
     */
    function depositToCompound(CErc20 market, uint256 amountToDeposit) public {
        ERC20 tokenToDeposit = ERC20(market.underlying());
        amountToDeposit = _maxAvailable(tokenToDeposit, amountToDeposit);
        tokenToDeposit.safeApprove(address(market), amountToDeposit);
        market.mint(amountToDeposit);
    }

    /**
     * @notice Allows strategists to withdraw assets from Compound.
     * @param market the market to withdraw from.
     * @param amountToWithdraw the amount of `market.underlying()` to withdraw from Compound
     */
    function withdrawFromCompound(CErc20 market, uint256 amountToWithdraw) public {
        market.redeemUnderlying(amountToWithdraw);
    }

    /**
     * @notice Allows strategists to claim COMP rewards.
     */
    function claimComp() public {
        comptroller().claimComp(address(this));
    }

    /**
     * @notice Allows strategists to claim COMP and immediately swap it using oracleSwap.
     * @param assetOut the ERC20 asset to get out of the swap
     * @param exchange UniV2 or UniV3 exchange to make the swap on
     * @param params swap params containing path and poolFees(if UniV3)
     * @param slippage number less than 1e18, defining the max swap slippage
     */
    function claimCompAndSwap(
        ERC20 assetOut,
        SwapRouter.Exchange exchange,
        bytes memory params,
        uint64 slippage
    ) public {
        uint256 balance = COMP().balanceOf(address(this));
        claimComp();
        balance = COMP().balanceOf(address(this)) - balance;
        oracleSwap(COMP(), assetOut, balance, exchange, params, slippage);
    }
}
