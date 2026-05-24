// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {MockMoreDscThanCollateral} from "../mocks/MockMoreDscThanCollateral.sol";

contract DSCEngineTest is Test {
    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    DecentralizedStableCoin dsc;
    DSCEngine engine;
    DeployDSC deployer;
    HelperConfig config;

    address cnyPriceFeedAddress;
    address wEthPriceFeed;
    address wBtcPriceFeed;
    address wEth;
    address wBTC;
    uint256 deployerKey;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_BALANCE = 10 ether;
    uint256 public constant AMOUNT_TO_MINT = 1000 ether;
    uint256 public constant AMOUNT_TO_REDEEM = 5 ether;
    uint256 public constant AMOUNT_TO_COVER = 20 ether; // two times AMOUNT_COLLATERAL of the user

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(wEth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
        _;
    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);
        engine.depositCollateralAndMintDsc(wEth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        int256 newEthPrice = 18e8; // 1 ETH = 18 USD, therefore HF = 0.9
        MockV3Aggregator(wEthPriceFeed).updateAnswer(newEthPrice);

        ERC20Mock(wEth).mint(LIQUIDATOR, AMOUNT_TO_COVER);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_TO_COVER);
        engine.depositCollateralAndMintDsc(wEth, AMOUNT_TO_COVER, AMOUNT_TO_MINT);

        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.liquidate(wEth, USER, AMOUNT_TO_MINT);

        vm.stopPrank();
        _;
    }

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (cnyPriceFeedAddress, wEthPriceFeed, wBtcPriceFeed, wEth, wBTC, deployerKey) = config.activeNetworkConfig();

        ERC20Mock(wEth).mint(USER, STARTING_BALANCE);
    }

    ////////////////////////////////////
    /////////// CONSTRUCTOR ////////////
    ////////////////////////////////////

    function testConstructorRevertsIfTokenLengthAndPriceFeedLengthDoNotMatch() public {
        tokenAddresses.push(wEth);
        priceFeedAddresses.push(wEthPriceFeed);
        tokenAddresses.push(wBTC);
        // priceFeedAddresses.push(wBtcPriceFeed); - intentionally do not push wBtcPriceFeed to priceFeedAddresses

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeTheSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, cnyPriceFeedAddress, address(dsc));
    }

    ////////////////////////////////////
    ///////////// GETTERS //////////////
    ////////////////////////////////////

    function testGetAccountCollateralValueCny() public depositedCollateral {
        uint256 expectedCollateralValueCny = engine.getCnyValue(wEth, AMOUNT_COLLATERAL);
        uint256 actualCollateralValueCny = engine.getAccountCollateralValueCny(USER);

        assertEq(expectedCollateralValueCny, actualCollateralValueCny);
    }

    function testGetAccountCollateralValueUsd() public depositedCollateral {
        uint256 expectedCollateralValueUsd = engine.getUsdValue(wEth, AMOUNT_COLLATERAL);
        uint256 actualCollateralValueUsd = engine.getAccountCollateralValueUsd(USER);

        assertEq(expectedCollateralValueUsd, actualCollateralValueUsd);
    }

    /*
     * @notice expectedCnyValue is calculated by multiplying usdValue & cnyPerUsd (price feed).
     * Since the current blockchain is Anvil, usdValue uses WETH_PRICE from HelperConfig which is 2000e18.
     *
     * @notice in assertion we use cnyPrice_e19 format to consider 20_000e18 value, an equivalent to 2000e19
     */

    function testGetCnyValue() public view {
        uint256 wEthAmount = 10 ether;
        uint256 usdValue = 20_000e18; // 10 ETH = 2000 USD * 10 = 20_000 USD
        uint256 cnyPerUsd = engine.getCnyPerUsd(); // 1 CNY = 0.148 USD => 1 USD = 1 / 0.148 CNY = 6.756756756756756756 CNY
        uint256 decimal_precision = engine.getDecimalPrecision(); // 1e18

        uint256 expectedCnyValue = (usdValue * cnyPerUsd) / decimal_precision; // 2000 USD * 6.756756756756756756 CNY/USD = 13_513.513513513513512 CNY
        uint256 actualCnyValue = engine.getCnyValue(wEth, wEthAmount);

        assertEq(expectedCnyValue, actualCnyValue);

        // 10 ETH ≈ 135135 CNY, so check we're in the right order of magnitude
        assert(actualCnyValue > 135135e18);
        assert(actualCnyValue < 135145e18);
    }

    function testGetUsdValue() public view {
        uint256 wEthAmount = 10 ether;
        uint256 expectedUsdValue = 20_000e18; // 10 ETH = 2000 USD * 10 = 20_000 USD
        uint256 actualUsdValue = engine.getUsdValue(wEth, wEthAmount);

        assertEq(expectedUsdValue, actualUsdValue);
    }

    function testGetCnyPerUsd() public view {
        uint256 expectedCnyPerUsd = 6_756756756756756756; // 1 USD = 6.756756756756756756 CNY
        uint256 actualCnyPerUsd = engine.getCnyPerUsd();

        assertEq(expectedCnyPerUsd, actualCnyPerUsd);
    }

    function testGetCnyFromUsd() public view {
        uint256 usdAmount = 20_000e18;
        uint256 expectedCnyAmount = 135_135.13513513513512e18; // 20_000 USD * 6.756756756756756756 CNY/USD = 135_135.13513513513512 CNY
        uint256 actualCnyAmount = engine.getCnyFromUsd(usdAmount);

        assertEq(expectedCnyAmount, actualCnyAmount);
    }

    function testGetUsdFromCny() public view {
        uint256 cnyAmount = 135_135.13513513513512e18; // 20_000 USD * 6.756756756756756756 CNY/USD = 135_135.13513513513512 CNY
        uint256 expectedUsdAmount = 20_000e18;
        uint256 actualUsdAmount = engine.getUsdFromCny(cnyAmount);

        assertEq(expectedUsdAmount, actualUsdAmount);
    }

    /*
     * @notice cnyAmount is pre-calculated by using an expected USD price = 20_000;
     * Since the current blockchain is Anvil, usdValue uses WETH_PRICE from HelperConfig which is 2000e18:
     *
     * cnyAmount: 135_135.13513513513512 CNY = 20_000 USD * 6.756756756756756756 CNY/USD
     *
     */

    function testGetTokenAmountFromCny() public view {
        uint256 cnyAmount = 135_135.13513513513512e18;
        uint256 expectedEthAmount = 10 ether;

        // uint256 usdValue = engine.getUsdFromCny(cnyAmount); // 13_513.513513513513512 CNY * 0.148 USD/CNY = 2000 USD
        uint256 actualEthAmount = engine.getTokenAmountFromCny(wEth, cnyAmount);

        assertEq(actualEthAmount, expectedEthAmount);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 20_000e18; // 10 ETH = 2000 USD * 10 = 20_000 USD
        uint256 expectedEthAmount = 10 ether;
        uint256 actualEthAmount = engine.getTokenAmountFromUsd(wEth, usdAmount);

        assertEq(actualEthAmount, expectedEthAmount);
    }

    function testGetAccountInformation() public depositedCollateralAndMintedDsc {
        uint256 expectedCollateralValueCny = engine.getCnyValue(wEth, AMOUNT_COLLATERAL);
        uint256 expectedDscMinted = AMOUNT_TO_MINT;
        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(collateralValueCny, expectedCollateralValueCny);
    }

    function testCalculateHealthFactor() public depositedCollateralAndMintedDsc {
        uint256 liquidation_adjustment = engine.getLiquidationAdjustment();
        uint256 liquidation_precision = engine.getLiquidationPrecision();
        uint256 decimal_precision = engine.getDecimalPrecision();

        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);
        uint256 collateralAdjustedForThreshold = (collateralValueCny * liquidation_adjustment) / liquidation_precision;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * decimal_precision) / totalDscMinted;
        uint256 expectedHealthFactorInEther = engine.getCnyFromUsd(10 ether);

        uint256 actualHealthFactor = engine.calculateHealthFactor(totalDscMinted, collateralValueCny);

        assertEq(actualHealthFactor, expectedHealthFactor);
        assertEq(actualHealthFactor, expectedHealthFactorInEther);
    }

    function testGetHealthFactor() public depositedCollateralAndMintedDsc {
        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(totalDscMinted, collateralValueCny);
        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        uint256 expectedHealthFactorInEther = engine.getCnyFromUsd(10 ether);

        assertEq(actualHealthFactor, expectedHealthFactor);
        assertEq(actualHealthFactor, expectedHealthFactorInEther);
    }

    function testGetCollateralTokens() public view {
        address[] memory expectedCollateralTokens = new address[](2);
        expectedCollateralTokens[0] = wEth;
        expectedCollateralTokens[1] = wBTC;

        address[] memory actualCollateralTokens = engine.getCollateralTokens();

        assertEq(expectedCollateralTokens.length, actualCollateralTokens.length);
        assert(expectedCollateralTokens[0] == actualCollateralTokens[0]);
        assert(expectedCollateralTokens[1] == actualCollateralTokens[1]);
    }

    function testGetCollateralBalanceOfUser() public depositedCollateral {
        uint256 expectedCollateralBalance = AMOUNT_COLLATERAL;
        uint256 actualCollateralBalance = engine.getCollateralBalanceOfUser(USER, wEth);

        assertEq(expectedCollateralBalance, actualCollateralBalance);
    }

    function testGetPriceFeed() public view {
        address expectedWethPriceFeed = wEthPriceFeed;
        address expectedWbtcPriceFeed = wBtcPriceFeed;
        address actualWethPriceFeed = engine.getPriceFeed(wEth);
        address actualWbtcPriceFeed = engine.getPriceFeed(wBTC);

        assertEq(expectedWethPriceFeed, actualWethPriceFeed);
        assertEq(expectedWbtcPriceFeed, actualWbtcPriceFeed);
    }

    function testGetDsc() public view {
        address expectedDscAddress = address(dsc);
        address actualDscAddress = engine.getDsc();

        assertEq(expectedDscAddress, actualDscAddress);
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 expectedAdditionalFeedPrecision = 1e10;
        uint256 actualAdditionalFeedPrecision = engine.getAdditionalFeedPrecision();

        assertEq(expectedAdditionalFeedPrecision, actualAdditionalFeedPrecision);
    }

    function testGetDecimalPrecision() public view {
        uint256 expectedDecimalPrecision = 1e18;
        uint256 actualDecimalPrecision = engine.getDecimalPrecision();

        assertEq(expectedDecimalPrecision, actualDecimalPrecision);
    }

    function testGetLiquidationAdjustment() public view {
        uint256 expectedLiquidationAdjustment = 50; // 50% collateral value is considered for liquidation
        uint256 actualLiquidationAdjustment = engine.getLiquidationAdjustment();

        assertEq(expectedLiquidationAdjustment, actualLiquidationAdjustment);
    }

    function testGetLiquidationPrecision() public view {
        uint256 expectedLiquidationPrecision = 100; // liquidation adjustment is divided by 100 to get the percentage
        uint256 actualLiquidationPrecision = engine.getLiquidationPrecision();

        assertEq(expectedLiquidationPrecision, actualLiquidationPrecision);
    }

    function testGetLiquidationBonus() public view {
        uint256 expectedLiquidationBonus = 10; // liquidator gets 10% bonus on top of the collateral value they cover
        uint256 actualLiquidationBonus = engine.getLiquidationBonus();

        assertEq(expectedLiquidationBonus, actualLiquidationBonus);
    }

    function testGetMinHealthFactor() public view {
        uint256 expectedMinHealthFactor = 1e18; // health factor is calculated with 18 decimals precision, so 1 is represented as 1e18
        uint256 actualMinHealthFactor = engine.getMinHealthFactor();

        assertEq(expectedMinHealthFactor, actualMinHealthFactor);
    }

    ////////////////////////////////////
    //////// DEPOSIT_COLLATERAL ////////
    ////////////////////////////////////

    /*
     * @notice most functions use transferFrom (ERC20Mock.sol) which requires approval;
     * For that reason, ERC20Mock().approve() is used to make sure that the function does not revert
     * because transferFrom failed.
     */

    function testDepositCollateralRevertsIfZero() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralRevertsIfNotAllowedToken() public {
        ERC20Mock notAllowedToken = new ERC20Mock();
        ERC20Mock(address(notAllowedToken)).mint(USER, STARTING_BALANCE);

        vm.startPrank(USER);
        ERC20Mock(address(notAllowedToken)).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateral(address(notAllowedToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateral() public {
        uint256 expectedValueDeposited = engine.getCnyValue(wEth, AMOUNT_COLLATERAL);

        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        uint256 balanceBefore = engine.getAccountCollateralValueCny(USER);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        uint256 balanceAfter = engine.getAccountCollateralValueCny(USER);

        vm.stopPrank();
        assertEq(balanceBefore + expectedValueDeposited, balanceAfter);
    }

    function testDepositCollateralEmitsEvent() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectEmit();
        emit CollateralDeposited(USER, wEth, AMOUNT_COLLATERAL);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGetAccountInformation() public depositedCollateral {
        uint256 expectedDscMinted = 0;
        uint256 expectedCollateralValueCny = engine.getCnyValue(wEth, AMOUNT_COLLATERAL);
        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(collateralValueCny, expectedCollateralValueCny);
    }

    ////////////////////////////////////
    ///////////// MINT_DSC /////////////
    ////////////////////////////////////

    function testMintRevertsIfZeroMinted() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintRevertsIfHealthFactorIsBroken() public {
        uint256 collateralValueInCny = engine.getAccountCollateralValueCny(USER);
        uint256 expectedHealthFactor = engine.calculateHealthFactor(AMOUNT_TO_MINT, collateralValueInCny);

        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, expectedHealthFactor)
        );
        engine.mintDsc(AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanMint() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        uint256 mintedBefore = dsc.balanceOf(USER);
        engine.depositCollateral(wEth, AMOUNT_COLLATERAL);
        engine.mintDsc(AMOUNT_TO_MINT);
        uint256 mintedAfter = dsc.balanceOf(USER);
        vm.stopPrank();

        assertEq(mintedBefore + AMOUNT_TO_MINT, mintedAfter);
    }

    //////////////////////////////////////////////////
    //////// DEPOSIT_COLLATERAL_AND_MINT_DSC /////////
    //////////////////////////////////////////////////

    function testDepositCollateralAndMintDscRevertsIfZeroAmount() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.depositCollateralAndMintDsc(wEth, 0, 0);
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDscRevertsIfNotAllowedToken() public {
        ERC20Mock notAllowedToken = new ERC20Mock();
        ERC20Mock(address(notAllowedToken)).mint(USER, STARTING_BALANCE);

        vm.startPrank(USER);
        ERC20Mock(address(notAllowedToken)).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.depositCollateralAndMintDsc(address(notAllowedToken), AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(engine), AMOUNT_COLLATERAL);

        uint256 mintedBefore = dsc.balanceOf(USER);
        engine.depositCollateralAndMintDsc(wEth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        uint256 mintedAfter = dsc.balanceOf(USER);
        vm.stopPrank();

        assertEq(mintedBefore + AMOUNT_TO_MINT, mintedAfter);
    }

    function testCanDepositCollateralAndMintDscAndGetAccountInformation() public depositedCollateralAndMintedDsc {
        uint256 expectedDscMinted = AMOUNT_TO_MINT;
        uint256 expectedCollateralValueCny = engine.getCnyValue(wEth, AMOUNT_COLLATERAL);
        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);

        assertEq(totalDscMinted, expectedDscMinted);
        assertEq(collateralValueCny, expectedCollateralValueCny);
    }

    ////////////////////////////////////
    //////// REDEEM_COLLATERAL /////////
    ////////////////////////////////////

    function testRedeemCollateralRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateral(wEth, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateral() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        uint256 userBalanceCnyBeforeRedeem = engine.getAccountCollateralValueCny(USER);
        assertEq(userBalanceCnyBeforeRedeem, engine.getCnyValue(wEth, AMOUNT_COLLATERAL));

        engine.redeemCollateral(wEth, AMOUNT_TO_REDEEM);
        uint256 userBalanceCnyAfterRedeem = engine.getAccountCollateralValueCny(USER);
        assertEq(userBalanceCnyAfterRedeem, engine.getCnyValue(wEth, AMOUNT_COLLATERAL - AMOUNT_TO_REDEEM));

        vm.stopPrank();
    }

    function testCannotRedeemCollateralIfHealthFactorIsBroken() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        engine.redeemCollateral(wEth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ////////////////////////////////////////////
    //////// REDEEM_COLLATERAL_FOR_DSC /////////
    ////////////////////////////////////////////

    function testRedeemCollateralForDscRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.redeemCollateralForDsc(wEth, 0, 0);
        vm.stopPrank();
    }

    function testCanRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.redeemCollateralForDsc(wEth, AMOUNT_TO_REDEEM, AMOUNT_TO_MINT);

        uint256 userCollateralValueCnyAfterRedeem = engine.getAccountCollateralValueCny(USER);
        uint256 expectedCollateralValueCnyAfterRedeem = engine.getCnyValue(wEth, AMOUNT_COLLATERAL - AMOUNT_TO_REDEEM);

        vm.stopPrank();

        assertEq(userCollateralValueCnyAfterRedeem, expectedCollateralValueCnyAfterRedeem);
        assertEq(dsc.balanceOf(USER), 0);
    }

    function testCannotRedeemCollateralForDscIfHealthFactorIsBroken() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        dsc.approve(address(engine), AMOUNT_TO_MINT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        engine.redeemCollateralForDsc(wEth, AMOUNT_COLLATERAL, 1e18);
        vm.stopPrank();
    }

    ////////////////////////////////////
    ///////////// BURN_DSC /////////////
    ////////////////////////////////////

    function testBurnDscRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.burnDsc(0);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);

        dsc.approve(address(engine), AMOUNT_TO_MINT);
        engine.burnDsc(AMOUNT_TO_MINT);
        uint256 userBalanceAfterBurn = dsc.balanceOf(USER);

        vm.stopPrank();

        assertEq(userBalanceAfterBurn, 0);
    }

    ////////////////////////////////////
    //////////// LIQUIDATE /////////////
    ////////////////////////////////////

    function testLiquidateRevertsIfZero() public depositedCollateralAndMintedDsc {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        engine.liquidate(wEth, USER, 0);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfNotAllowedToken() public {
        ERC20Mock notAllowedToken = new ERC20Mock();
        ERC20Mock(address(notAllowedToken)).mint(USER, STARTING_BALANCE);

        vm.startPrank(LIQUIDATOR);
        ERC20Mock(address(notAllowedToken)).approve(address(engine), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        engine.liquidate(address(notAllowedToken), USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorIsNormal() public depositedCollateralAndMintedDsc {
        ERC20Mock(wEth).mint(LIQUIDATOR, STARTING_BALANCE);
        vm.startPrank(LIQUIDATOR);
        uint256 userHealthFactor = engine.getHealthFactor(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsNormal.selector, userHealthFactor));
        engine.liquidate(wEth, USER, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorNotImproved() public {
        // Arranging Mocks
        tokenAddresses = [wEth];
        priceFeedAddresses = [wEthPriceFeed];
        address owner = msg.sender;
        MockMoreDscThanCollateral mockDsc = new MockMoreDscThanCollateral(owner, wEthPriceFeed);

        vm.startPrank(owner);
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, cnyPriceFeedAddress, address(mockDsc));
        mockDsc.transferOwnership(address(mockEngine));
        vm.stopPrank();

        // Arranging USER
        vm.startPrank(USER);
        ERC20Mock(wEth).approve(address(mockEngine), AMOUNT_COLLATERAL);
        ERC20Mock(wEth).mint(USER, AMOUNT_COLLATERAL);
        mockEngine.depositCollateralAndMintDsc(wEth, AMOUNT_COLLATERAL, AMOUNT_TO_MINT);
        vm.stopPrank();

        // Arranging LIQUIDATOR
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(wEth).approve(address(mockEngine), AMOUNT_TO_COVER);
        ERC20Mock(wEth).mint(LIQUIDATOR, AMOUNT_TO_COVER);
        mockEngine.depositCollateralAndMintDsc(wEth, AMOUNT_TO_COVER, AMOUNT_TO_MINT);
        mockDsc.approve(address(mockEngine), AMOUNT_TO_MINT);

        // Act
        int256 newEthPrice = 18e8; // ETH price crashes to 18 USD, therefore HF = 0.9
        MockV3Aggregator(wEthPriceFeed).updateAnswer(newEthPrice);

        // cover only 10% of the debt
        // to avoid getting "type(uint256).max" in HealthFactor calculation and check
        uint256 debtToCover = AMOUNT_TO_MINT / 10;

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorNotImproved.selector, 0));
        mockEngine.liquidate(wEth, USER, debtToCover);
        vm.stopPrank();
    }

    function testLiquidateTheExactAmount() public liquidated {
        uint256 liquidation_precision = engine.getLiquidationPrecision();
        uint256 liquidation_bonus = engine.getLiquidationBonus();

        uint256 tokenAmountToCover = engine.getTokenAmountFromCny(wEth, AMOUNT_TO_MINT);
        uint256 liquidatorBonus = (tokenAmountToCover * liquidation_bonus) / liquidation_precision;

        uint256 expectedAmountLiquidated = tokenAmountToCover + liquidatorBonus;
        uint256 cnyExpectedAmountLiquidated = engine.getCnyValue(wEth, expectedAmountLiquidated);

        uint256 collateralAfterLiquidation = engine.getCollateralBalanceOfUser(USER, wEth);
        uint256 amountLiquidated = AMOUNT_COLLATERAL - collateralAfterLiquidation;
        uint256 cnyValueLiquidated = engine.getCnyValue(wEth, amountLiquidated);

        assertEq(cnyValueLiquidated, cnyExpectedAmountLiquidated);
    }

    function testLiquidateToCorrectBalance() public liquidated {
        uint256 liquidation_precision = engine.getLiquidationPrecision();
        uint256 liquidation_bonus = engine.getLiquidationBonus();

        (uint256 dscMintedAfterLiquidation, uint256 collateralAfterLiquidation) = engine.getAccountInformation(USER);

        uint256 tokenAmountToCover = engine.getTokenAmountFromCny(wEth, AMOUNT_TO_MINT);
        uint256 liquidatorBonus = (tokenAmountToCover * liquidation_bonus) / liquidation_precision;

        uint256 expectedAmountLiquidated = tokenAmountToCover + liquidatorBonus;
        uint256 expectedCollateralAfterLiquidation = AMOUNT_COLLATERAL - expectedAmountLiquidated;
        uint256 cnyExpectedCollateralAfterLiquidation = engine.getCnyValue(wEth, expectedCollateralAfterLiquidation);

        assertEq(collateralAfterLiquidation, cnyExpectedCollateralAfterLiquidation);
        assertEq(dscMintedAfterLiquidation, 0);
    }

    function testLiquidatorPaymentIsCorrect() public liquidated {
        uint256 liquidation_precision = engine.getLiquidationPrecision();
        uint256 liquidation_bonus = engine.getLiquidationBonus();

        uint256 expectedLiquidatorBalance = engine.getTokenAmountFromCny(wEth, AMOUNT_TO_MINT)
            + (engine.getTokenAmountFromCny(wEth, AMOUNT_TO_MINT) * liquidation_bonus) / liquidation_precision;
        uint256 liquidatorBalance = ERC20Mock(wEth).balanceOf(LIQUIDATOR);

        assertEq(expectedLiquidatorBalance, liquidatorBalance);
    }

    function testLiquidatorReceivesUserDsc() public liquidated {
        (uint256 liquidatorDscMinted,) = engine.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_TO_MINT);
    }

    ////////////////////////////////////
    ////////// HEALTH_FACTOR ///////////
    ////////////////////////////////////

    function testHealthFactorIsCorrect() public depositedCollateralAndMintedDsc {
        uint256 liquidation_adjustment = engine.getLiquidationAdjustment();
        uint256 liquidation_precision = engine.getLiquidationPrecision();
        uint256 decimal_precision = engine.getDecimalPrecision();

        vm.startPrank(USER);

        (uint256 totalDscMinted, uint256 collateralValueCny) = engine.getAccountInformation(USER);
        uint256 collateralAdjustedForThreshold = (collateralValueCny * liquidation_adjustment) / liquidation_precision;
        uint256 expectedHealthFactor = (collateralAdjustedForThreshold * decimal_precision) / totalDscMinted;

        uint256 actualHealthFactor = engine.getHealthFactor(USER);
        assertEq(actualHealthFactor, expectedHealthFactor);

        vm.stopPrank();
    }

    function testHealthFactorCanBecomeLessThanOne() public depositedCollateralAndMintedDsc {
        // HF before: 20_000 (price) * 50 (l_adj) / 100 (l_prec) = 10_000
        // 10_000 / 100 = 100
        int256 newEthPrice = 18e8; // 1 ETH = 18 USD
        MockV3Aggregator(wEthPriceFeed).updateAnswer(newEthPrice);

        uint256 userHealhFactorAfterPriceChange = engine.getHealthFactor(USER);
        // HF after: 18 * 10 (precision) * 50 (l_adj) / 100 (l_prec) = 90
        // 90 / 1000 (minted) = 0.09
        // After that, calculate USD to CNY

        uint256 expectedHealthFactor = engine.getCnyFromUsd(9 ether / 100);

        assertEq(userHealhFactorAfterPriceChange, expectedHealthFactor);
    }

    function testHealthFactorIsMaxWithNoDebt() public depositedCollateral {
        assertEq(engine.getHealthFactor(USER), type(uint256).max);
    }

    ////////////////////////////////////
    //////////// ORACLE_LIB ////////////
    ////////////////////////////////////

    function testRevertsOnStalePrice() public {
        vm.warp(block.timestamp + 5 hours); // warp to make the price feed stale
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        engine.getUsdValue(wEth, AMOUNT_COLLATERAL);
    }

    function testDoesNotRevertWithFreshPrice() public view {
        // should pass without reverting
        engine.getUsdValue(wEth, 1 ether);
    }

    function testRevertsOnStaleCnyPrice() public {
        vm.warp(block.timestamp + 5 hours); // warp to make the price feed stale
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        engine.getCnyValue(wEth, AMOUNT_COLLATERAL);
    }
}
