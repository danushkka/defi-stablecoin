// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * @title DSCEngine
 * @author daniko
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1 CNY peg at all times.
 * This stablecoin has the following properties:
 * - Exogenously Collateralized
 * - Chinese Yuan Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI with no governance, no fees, and backed by only wETH and wBTC.
 *
 * The DSC system should always be overcollateralized. It means that the value of
 * all collateral should always be greater than the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for interactions with the DSC including minting, burning, depositing collateral, redeeming collateral, and liquidations.
 * @notice This contract is based on the MakerDAO DSS system
 */

contract DSCEngine is ReentrancyGuard {
    ////////////////////////////////////
    ////////////// ERRORS //////////////
    ////////////////////////////////////

    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 userHealthFactor);
    error DSCEngine__HealthFactorIsNormal(uint256 userHealthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 userHealthFactor);
    error DSCEngine__MintingFailed();

    ////////////////////////////////////
    ////////////// TYPES ///////////////
    ////////////////////////////////////

    using OracleLib for AggregatorV3Interface;

    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant DECIMAL_PRECISION = 1e18;
    uint256 private constant LIQUIDATION_ADJUSTMENT = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; // points token to priceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; // point user to (the token and the amount) they deposited
    mapping(address user => uint256 amountMinted) private s_DSCEMinted; // point user to the amount of DSC they have minted

    address[] private s_collateralTokens;

    AggregatorV3Interface private immutable i_cnyPriceFeed;
    DecentralizedStableCoin private immutable i_dsc;

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory tokenPriceFeedAddresses,
        address cnyPriceFeedAddress,
        address dscAddress
    ) {
        if (tokenAddresses.length != tokenPriceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength();
        }
        for (uint256 token = 0; token < tokenAddresses.length; token++) {
            s_priceFeeds[tokenAddresses[token]] = tokenPriceFeedAddresses[token];
            s_collateralTokens.push(tokenAddresses[token]);
        }
        i_cnyPriceFeed = AggregatorV3Interface(cnyPriceFeedAddress);
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ////////////////////////////////////
    //////// PUBLIC & EXTERNAL /////////
    ////////////////////////////////////

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) nonReentrant {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
        _mintDsc(amountDscToMint);
    }

    /*
    * @param tokenCollateralAddress: address of the token to be deposited as Collateral
    * @param amount: amount to be deposited
    */

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        isAllowedToken(tokenCollateralAddress)
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _depositCollateral(tokenCollateralAddress, amountCollateral);
    }

    function mintDsc(uint256 amountToMint) public moreThanZero(amountToMint) nonReentrant {
        _mintDsc(amountToMint);
    }

    /*
     * @param tokenCollateralAddress: address of the token to be redeemed as Collateral
     * @param amountCollateralToRedeem: amount to be redeemed
     * @param amountDscToBurn: amount of DSC to be burned in order to redeem collateral
     *
     * This function burns the DSC and redeems the collateral in the same transaction
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountDscToBurn
    ) external moreThanZero(amountCollateralToRedeem) isAllowedToken(tokenCollateralAddress) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice health factor should be above 1e18 after this function is called, otherwise the transaction will revert
     */

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateralToRedeem)
        public
        moreThanZero(amountCollateralToRedeem)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateralToRedeem);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amountDscToBurn) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(msg.sender, msg.sender, amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // unlikely to be needed
    }

    /*
     * @param collateral: address of the collateral to be liquidated
     * @param user: address of the user to liquidate
     * @param debtToCover: amount of DSC to burn from the user to cover the debt
     *
     * @notice This function allows anyone to liquidate a user that is undercollateralized.
     * The liquidator will burn the user's DSC and receive a portion of the user's collateral (10%) in return.
     * This will keep the protocol overcollateralized and therfore healthy.
     */

    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        uint256 startingHeathFactor = _healthFactor(user);
        if (startingHeathFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsNormal(startingHeathFactor);
        }

        uint256 tokenAmountToCover = getTokenAmountFromCny(tokenCollateralAddress, debtToCover);
        uint256 bonusForLiquidator = (tokenAmountToCover * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountToCover + bonusForLiquidator;

        _burnDsc(msg.sender, user, debtToCover);
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);

        uint256 endingHealthFactor = _healthFactor(user);
        if (endingHealthFactor <= startingHeathFactor) {
            revert DSCEngine__HealthFactorNotImproved(endingHealthFactor);
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueCny) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueCny);
    }

    ////////////////////////////////////
    //////// PRIVATE & INTERNAL ////////
    ////////////////////////////////////

    function _depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _mintDsc(uint256 amountToMint) private {
        // Update state first, then verify — if HF breaks, entire tx reverts
        s_DSCEMinted[msg.sender] += amountToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountToMint);
        if (!minted) {
            revert DSCEngine__MintingFailed();
        }
    }

    function _burnDsc(address from, address user, uint256 amountDscToBurn) private {
        s_DSCEMinted[user] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(from, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateralToRedeem;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateralToRedeem);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateralToRedeem);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getCnyPerUsd() private view returns (uint256) {
        (, int256 cnyPrice,,,) = i_cnyPriceFeed.stalePriceCheck();
        // casting to 'uint256' is safe because cnyPrice will always be positive
        // forge-lint: disable-next-line(unsafe-typecast)
        return (DECIMAL_PRECISION * DECIMAL_PRECISION) / (uint256(cnyPrice) * ADDITIONAL_FEED_PRECISION);
    }

    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        return (s_DSCEMinted[user], getAccountCollateralValueCny(user));
    }

    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueCny) private pure returns (uint256) {
        // NOTE: partial liquidations must leave some debt remaining
        // or this will return max and bypass DSCEngine__HealthFactorNotImproved() check
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueCny * LIQUIDATION_ADJUSTMENT) / LIQUIDATION_PRECISION;
        return ((collateralAdjustedForThreshold * DECIMAL_PRECISION) / totalDscMinted);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInCny) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInCny);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);

        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    /*
     * @param user: address of the user to get the collateral value for
     * @notice These functions use getUsdValue() and getCnyValue() to calculate the USD/CNY value of each collateral token
     * @return total collateral value of all tokens in USD/CNY for a given user
     */

    function getAccountCollateralValueUsd(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValue += getUsdValue(token, amount);
        }

        return totalCollateralValue;
    }

    function getAccountCollateralValueCny(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];

            totalCollateralValue += getCnyValue(token, amount);
        }

        return totalCollateralValue;
    }

    /*
     * @param token: address of the token to get the USD value for
     * @param amount: amount of the token to get the USD value for
     *
     * @notice This function uses Chainlink price feeds to get the price of the collateral tokens in USD,
     * and then calculates the total value of the collateral in USD.
     */

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 usdPrice,,,) = priceFeed.stalePriceCheck();

        // casting to 'uint256' is safe because usdPrice will always be positive
        // forge-lint: disable-next-line(unsafe-typecast)
        return ((uint256(usdPrice) * ADDITIONAL_FEED_PRECISION) * amount) / DECIMAL_PRECISION;
    }

    /*
     * @notice This function is similar to getUsdValue,
     * but it converts the USD value to CNY value using the CNY/USD price feed.
     * This is used to maintain the 1 DSC == 1 CNY peg.
     */

    function getCnyValue(address token, uint256 tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 usdPrice,,,) = priceFeed.stalePriceCheck();

        // casting to 'uint256' is safe because usdPrice will always be positive
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 usdValue = (uint256(usdPrice) * ADDITIONAL_FEED_PRECISION) * tokenAmount / DECIMAL_PRECISION;
        uint256 cnyPerUsd = _getCnyPerUsd();

        return (cnyPerUsd * usdValue / DECIMAL_PRECISION);
    }

    function getCnyPerUsd() public view returns (uint256) {
        return _getCnyPerUsd();
    }

    /*
     * @notice These functions allow to convert between USD and CNY values using the CNY/USD price feed.
     */

    function getCnyFromUsd(uint256 usdValue) public view returns (uint256) {
        uint256 cnyPerUsd = _getCnyPerUsd();
        return (usdValue * cnyPerUsd) / DECIMAL_PRECISION;
    }

    function getUsdFromCny(uint256 cnyValue) public view returns (uint256) {
        uint256 cnyPerUsd = _getCnyPerUsd();
        return (cnyValue * DECIMAL_PRECISION) / cnyPerUsd;
    }

    /*
     * @param token: address of the token to get the amount for
     * @param usdAmount: amount in USD/CNY to get the token amount for
     *
     * @notice This function uses Chainlink price feeds to get the price of the collateral tokens
     * in USD/CNY, and then calculates the amount of the token needed to get the given USD amount.
     */

    function getTokenAmountFromUsd(address token, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();

        // casting to 'uint256' is safe because price will always be positive
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 tokenAmount = (usdAmount * DECIMAL_PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
        return tokenAmount;
    }

    function getTokenAmountFromCny(address token, uint256 cnyAmount) public view returns (uint256) {
        uint256 usdAmount = getUsdFromCny(cnyAmount);
        uint256 tokenAmount = getTokenAmountFromUsd(token, usdAmount);
        return tokenAmount;
    }

    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalDscMinted, uint256 collateralValueCny)
    {
        (totalDscMinted, collateralValueCny) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return uint256(_healthFactor(user));
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getDecimalPrecision() external pure returns (uint256) {
        return DECIMAL_PRECISION;
    }

    function getLiquidationAdjustment() external pure returns (uint256) {
        return LIQUIDATION_ADJUSTMENT;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }
}
