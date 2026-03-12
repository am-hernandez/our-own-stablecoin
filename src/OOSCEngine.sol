// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {OurOwnStablecoin} from "./OurOwnStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/*
 * @title OOSCEngine
 * @author A.M. Hernandez
 * @notice The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg.
 * @notice This stablecoin has the following properties: Exogenous Collateral, Dollar-pegged, Algorithmically Stable.
 * @notice This stablecoin is like DAI without governance, fees, and only backed by WETH and WBTC.
 * @notice OOSC system should always be over collateralized. At no point should the value of all collateral be less than or equal to the value of all the OOSC.
 * @notice This contract is the core of the OOSC system. It handles all the logic for minting and redeeming OOSC, as well as depositing and withdrawing collateral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract OOSCEngine is ReentrancyGuard {
    //
    // ERRORS
    //

    error OOSCEngine_MustBeMoreThanZero();
    error OOSCEngine_OOSCAddressCannotBeZeroAddress();
    error OOSCEngine_TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error OOSCEngine_TokenNotAllowed();
    error OOSCEngine_TransferFailed();
    error OOSCEngine_BreaksHealthFactor(uint256 userHealthFactor);
    error OOSCEngine_HealthFactorOk();
    error OOSCEngine_HealthFactorNotImproved();
    error OOSCEngine_InvalidPrice();
    error OOSCEngine_MintFailed();
    error OOSCEngine_BurnAmountExceedsBalance();
    error OOSCEngine_NoCollateralToRedeem();

    //
    // STATE VARIABLES
    //

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% collateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountOoscMinted) private s_ooscMinted;
    address[] private s_collateralTokens;

    OurOwnStablecoin private immutable I_OOSC;

    //
    // EVENTS
    //

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    //
    // MODIFIERS
    //

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert OOSCEngine_TokenNotAllowed();
        }
        _;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert OOSCEngine_MustBeMoreThanZero();
        }
        _;
    }

    //
    // FUNCTIONS
    //

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address ooscAddress) {
        if (ooscAddress == address(0)) {
            revert OOSCEngine_OOSCAddressCannotBeZeroAddress();
        }
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert OOSCEngine_TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        I_OOSC = OurOwnStablecoin(ooscAddress);
    }

    //
    // EXTERNAL & PUBLIC FUNCTIONS
    //

    /*
     * @param tokenCollateralAddress The address of the token collateral to
     * deposit
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert OOSCEngine_TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress The address of the token collateral to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountOoscToMint The amount of OOSC to mint
     * @notice This function will deposit the collateral and mint the OOSC in a single transaction
     */
    function depositCollateralAndMintOosc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountOoscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintOosc(amountOoscToMint);
    }

    /*
     * @notice This function will burn the OOSC and redeem the collateral in a single transaction
     * @notice Health factor must be greater than 1 after collateral pulled
     * @param tokenCollateralAddress The address of the token collateral to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountOoscToBurn The amount of OOSC to burn/
     */
    function redeemCollateralForOosc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountOoscToBurn)
        public
        moreThanZero(amountOoscToBurn)
    {
        burnOosc(amountOoscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /*
     * @notice This function will redeem the collateral and burn the OOSC in a single transaction
     * @notice Health factor must be greater than 1 after collateral pulled
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorBroken(msg.sender);
    }

    /*
     * @param amountOoscToMint The amount of OOSC to mint
     * @notice The caller must have enough collateral deposited to mint the OOSC
     */
    function mintOosc(uint256 amountOoscToMint) public moreThanZero(amountOoscToMint) nonReentrant {
        s_ooscMinted[msg.sender] += amountOoscToMint;

        // if user attempts to mint more than the total collateral value, revert
        _revertIfHealthFactorBroken(msg.sender);

        bool minted = I_OOSC.mint(msg.sender, amountOoscToMint);
        if (!minted) {
            revert OOSCEngine_MintFailed();
        }
    }

    function burnOosc(uint256 amountOoscToBurn) public moreThanZero(amountOoscToBurn) {
        _burnOosc(amountOoscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorBroken(msg.sender);
    }

    /*
     * @param user The address of the user to liquidate, their health factor must be below the MIN_HEALTH_FACTOR
     * @param tokenCollateralAddress The address of the token collateral to liquidate
     * @param amountCollateral The amount of collateral to liquidate
     * @param amountOoscToBurn The amount of OOSC to burn/
     * @notice This function will liquidate the user's collateral if their health factor is less than 1
     * @notice The caller must have enough collateral deposited to liquidate the user
     * @notice Caller can partially liquidate the user's collateral
     * @notice Caller will receive a liquidationbonus for liquidating the user
     * @notice Function assumes overcollateralized user by 200%
     */
    function liquidate(address collateralToken, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        // check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert OOSCEngine_HealthFactorOk();
        }
        // want to burn their OOSC
        // and take their collateralToken
        // ex $140 ETH, $100 OOSC
        // debt to cover = $100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralToken, debtToCover);

        // and give them a 10% bonus
        // so give the liquidator 110$ USD of WETH for 100 OOSC

        // 0.05 ETH * 0.1 = 0.005 ETH, getting 0.055 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(user, msg.sender, collateralToken, totalCollateralToRedeem);

        // burn OOSC
        _burnOosc(debtToCover, user, msg.sender);

        // check if health factor is improved for user
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert OOSCEngine_HealthFactorNotImproved();
        }

        // check if health factor is broken for liquidator as well
        _revertIfHealthFactorBroken(msg.sender);
    }

    //
    // PRIVATE & INTERNAL FUNCTIONS
    //

    /*
     * @notice Burns the OOSC from the address of the user
     * @param amountOoscToBurn The amount of OOSC to burn
     * @param onBehalfOf The address of the user to burn the OOSC on behalf of
     * @param ooscFrom The address of the OOSC to burn from
     * @dev Low-level internal function, do not call unless the function
     * calling it is checking for health factors being broken
     */
    function _burnOosc(uint256 amountOoscToBurn, address onBehalfOf, address ooscFrom) private {
        if (s_ooscMinted[onBehalfOf] < amountOoscToBurn) {
            revert OOSCEngine_BurnAmountExceedsBalance();
        }

        s_ooscMinted[onBehalfOf] -= amountOoscToBurn;

        bool success = I_OOSC.transferFrom(ooscFrom, address(this), amountOoscToBurn);
        if (!success) {
            revert OOSCEngine_TransferFailed();
        }

        I_OOSC.burn(amountOoscToBurn);
    }

    /*
     * @notice Returns the total OOSC minted and the collateral value in USD
     * @param user The address of the user to get the account information of
     * @return totalOoscMinted The total OOSC minted by the user
     * @return collateralValueInUsd The collateral value in USD
    */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalOoscMinted, uint256 collateralValueInUsd)
    {
        totalOoscMinted = s_ooscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     * @notice Returns how close to liquidation the user is
     * @notice If user goes below 1, they get liquidated
     * @param user The address of the user to check the health factor of
     * @return The health factor of the user
     */
    function _healthFactor(address user) internal view returns (uint256) {
        // total OOSC minted
        // total collateral VALUE

        (uint256 totalOoscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        if (totalOoscMinted == 0) {
            return type(uint256).max; // no debt
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        // ex. 1000 ETH / 100 OOSC
        // 1000 * 50 = 50000 / 100 = (500 / 100) > 1
        return (collateralAdjustedForThreshold * PRECISION) / totalOoscMinted;
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        if (s_collateralDeposited[from][tokenCollateralAddress] == 0) {
            revert OOSCEngine_NoCollateralToRedeem();
        }

        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;

        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert OOSCEngine_TransferFailed();
        }
    }

    /*
     * @notice Reverts if the user does not have enough collateral
     * @param user The address of the user to check the health factor of
     */
    function _revertIfHealthFactorBroken(address user) internal view {
        // Check health factor, does user have enough collateral?
        // Revert if the user does not have enough collateral
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert OOSCEngine_BreaksHealthFactor(userHealthFactor);
        }
    }

    //
    // PUBLIC & EXTERNAL VIEW FUNCTIONS
    //

    /*
     * @notice Returns the caller's health factor (18 decimals). >= 1e18 is healthy, < 1e18 is liquidatable.
     */
    function getHealthFactor() external view returns (uint256) {
        return getHealthFactor(msg.sender);
    }

    /*
     * @notice Returns the health factor of an account (18 decimals). >= 1e18 is healthy, < 1e18 is liquidatable.
     * @param user The account to query.
     */
    function getHealthFactor(address user) public view returns (uint256) {
        return _healthFactor(user);
    }

    /*
     * @notice Given a USD value, returns how many units of the token that buys at the feed price.
     * @param token The collateral token (must have a price feed).
     * @param usdValue18Decimals USD value in 18 decimals (e.g. 100e18 = $100).
     * @return Token amount in token decimals (e.g. 18 for WETH) equivalent to usdValue18Decimals.
     */
    function getTokenAmountFromUsd(address token, uint256 usdValue18Decimals) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdValue18Decimals * PRECISION) / (SafeCast.toUint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token,
        // get the amount the user deposited,
        // and map it to the price to get the USD value

        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getTokenUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenUsdValue(address token, uint256 amount) public view returns (uint256) {
        // get the price feed of the token
        // get the price of the token
        // return the USD value

        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        // if (price <= 0) revert OOSCEngine_InvalidPrice();
        uint256 safePrice = SafeCast.toUint256(price);

        // ex. 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e8 (8 decimals for ETH)
        return ((safePrice * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalOoscMinted, uint256 collateralValueInUsd)
    {
        (totalOoscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }
}
